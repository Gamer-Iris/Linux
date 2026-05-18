#!/bin/bash

######################################################################################################################################################
# ファイル   : inventory_checks.sh
# 引数       : なし（setup.sh から source）
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# dynamic inventory / SSH / Ansible 疎通確認を担当する。対象ノードの状態変更は行わない。

######################################################################################################################################################
# check_inventory 関数
# @param  なし
# @return なし
# @error  ansible-inventory が inventory を生成できない場合は exit 1
# @note   settings_secret.yml の nodes 定義と inventory.sh の整合性を確認する。
######################################################################################################################################################
function check_inventory() {
  log "inventory 生成確認開始"

  if ! "${INVENTORY_SCRIPT}" --list >/dev/null; then
    log_error "inventory.sh の直接実行に失敗しました。実行権限、改行コード、settings_secret.yml を確認してください。"
    log_error "手動確認: cd ${SCRIPT_DIR} && ./inventory.sh --list | python3 -m json.tool"
    exit 1
  fi

  if ! ansible-inventory -i "${INVENTORY_SCRIPT}" --list >/dev/null; then
    log_error "inventory 生成失敗。settings_secret.yml の nodes.*.ip / username / key を確認してください。"
    log_error "手動確認: cd ${SCRIPT_DIR} && ./inventory.sh --list | python3 -m json.tool"
    exit 1
  fi

  log "inventory 生成確認完了"
}

######################################################################################################################################################
# check_ansible_ping 関数
# @param  なし
# @return なし
# @error  Ansible ping または become 確認に失敗した場合は exit 1
# @note   become 確認時のみ sudo password を inventory に露出させる。
######################################################################################################################################################
function check_ansible_ping() {
  log "Ansible ping 確認開始"
  local ansible_ssh_args="-F /dev/null -C -o ControlMaster=no -o ControlPath=none -o ControlPersist=no -o StrictHostKeyChecking=no"

  if ! ANSIBLE_SSH_ARGS="${ansible_ssh_args}" ansible all -i "${INVENTORY_SCRIPT}" -m ping >/dev/null; then
    log_error "Ansible ping 失敗。SSH 鍵、Python3、settings_secret.yml の nodes 設定を確認してください。"
    log_error "手動確認: ansible all -i ${INVENTORY_SCRIPT} -m ping"
    ANSIBLE_SSH_ARGS="${ansible_ssh_args}" ansible all -i "${INVENTORY_SCRIPT}" -m ping 2>&1 | tee -a "${LOG_FILE}" || true
    exit 1
  fi

  local failed_hosts=()
  local hosts
  local exposed_inventory
  exposed_inventory=$(LINUX_SETUP_EXPOSE_BECOME_PASSWORD=1 ansible-inventory -i "${INVENTORY_SCRIPT}" --list)
  hosts=$(printf '%s\n' "${exposed_inventory}" \
    | python3 -c 'import json,sys; inv=json.load(sys.stdin); print("\n".join(inv.get("_meta", {}).get("hostvars", {}).keys()))')

  local missing_password_hosts
  missing_password_hosts=$(printf '%s\n' "${exposed_inventory}" | python3 -c '
import json
import sys

inv = json.load(sys.stdin)
missing = []
for host, hostvars in inv.get("_meta", {}).get("hostvars", {}).items():
    password = hostvars.get("ansible_become_password") or hostvars.get("ansible_become_pass")
    if not password or password == "null" or "環境に合わせてください" in str(password):
        missing.append(host)
print(" ".join(missing))
')

  if [[ -n "${missing_password_hosts}" ]]; then
    log_error "Ansible become password が inventory に設定されていない host があります: ${missing_password_hosts}"
    log_error "settings_secret.yml の top-level password、または nodes.*[].password を設定してください。"
    exit 1
  fi

  local sudo_failed_hosts=()
  local sudo_entries
  sudo_entries=$(printf '%s\n' "${exposed_inventory}" | python3 -c '
import base64
import json
import sys

inv = json.load(sys.stdin)
for host, hostvars in inv.get("_meta", {}).get("hostvars", {}).items():
    fields = [
        host,
        hostvars.get("ansible_host", ""),
        hostvars.get("ansible_user", ""),
        hostvars.get("ansible_ssh_private_key_file", ""),
        hostvars.get("ansible_become_password") or hostvars.get("ansible_become_pass") or "",
    ]
    print("\t".join(base64.b64encode(str(field).encode()).decode() for field in fields))
')

  while IFS=$'\t' read -r host_b64 ip_b64 user_b64 key_b64 password_b64; do
    local host ip user key password
    host=$(printf '%s' "${host_b64}" | base64 -d)
    ip=$(printf '%s' "${ip_b64}" | base64 -d)
    user=$(printf '%s' "${user_b64}" | base64 -d)
    key=$(printf '%s' "${key_b64}" | base64 -d)
    password=$(printf '%s' "${password_b64}" | base64 -d)

    local sudo_probe_output
    sudo_probe_output=$(mktemp)
    if ! printf '%s\n' "${password}" | timeout 15s ssh -F /dev/null -i "${key}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        -o BatchMode=yes -T "${user}@${ip}" \
        "sudo -H -S -p '[sudo via setup] password:' -u root /bin/sh -c 'echo BECOME-SUCCESS-setup'" \
        >"${sudo_probe_output}" 2>&1; then
      sudo_failed_hosts+=("${host}")
      log_error "sudo -S 詳細確認失敗: ${host}"
      sed -e 's/^/  /' "${sudo_probe_output}" | tee -a "${LOG_FILE}" || true
    elif ! grep -q "BECOME-SUCCESS-setup" "${sudo_probe_output}"; then
      sudo_failed_hosts+=("${host}")
      log_error "sudo -S 詳細確認で成功マーカーを確認できません: ${host}"
      sed -e 's/^/  /' "${sudo_probe_output}" | tee -a "${LOG_FILE}" || true
    fi
    rm -f "${sudo_probe_output}"
  done <<< "${sudo_entries}"

  if [[ ${#sudo_failed_hosts[@]} -gt 0 ]]; then
    log_error "SSH 経由の sudo -S 確認に失敗した host があります: ${sudo_failed_hosts[*]}"
    log_error "settings_secret.yml の sudo password、または対象 host の sudo 権限 / sudoers 設定を確認してください。"
    exit 1
  fi

  log "sudoers 自動設定開始"
  while IFS=$'\t' read -r host_b64 ip_b64 user_b64 key_b64 password_b64; do
    local host ip user key password sudoers_line
    host=$(printf '%s' "${host_b64}" | base64 -d)
    ip=$(printf '%s' "${ip_b64}" | base64 -d)
    user=$(printf '%s' "${user_b64}" | base64 -d)
    key=$(printf '%s' "${key_b64}" | base64 -d)
    password=$(printf '%s' "${password_b64}" | base64 -d)

    if [[ ! "${user}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      log_error "sudoers に設定できない username です: ${host} (${user})"
      exit 1
    fi

    sudoers_line="${user} ALL=(ALL) NOPASSWD:ALL"
    if ! printf '%s\n' "${password}" | timeout 30s ssh -F /dev/null -i "${key}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        -o BatchMode=yes -T "${user}@${ip}" \
        "tmp=\$(mktemp) && trap 'rm -f \"\${tmp}\"' EXIT && printf '%s\n' '${sudoers_line}' >\"\${tmp}\" && sudo -S -p '' install -m 0440 \"\${tmp}\" /etc/sudoers.d/linux-setup && sudo -n visudo -cf /etc/sudoers.d/linux-setup" \
        >/dev/null 2>&1; then
      log_error "sudoers 自動設定に失敗しました: ${host} (${user}@${ip})"
      exit 1
    fi
  done <<< "${sudo_entries}"
  log "sudoers 自動設定完了"

  while IFS= read -r host; do
    [[ -z "${host}" ]] && continue
    if ! ANSIBLE_SSH_ARGS="${ansible_ssh_args}" LINUX_SETUP_EXPOSE_BECOME_PASSWORD=1 ansible "${host}" -i "${INVENTORY_SCRIPT}" -b -m command -a "true" >/dev/null; then
      failed_hosts+=("${host}")
    fi
  done <<< "${hosts}"

  if [[ ${#failed_hosts[@]} -gt 0 ]]; then
    log_error "Ansible become 確認失敗。settings_secret.yml の password（sudo パスワード）または sudo 権限を確認してください。"
    log_error "失敗 host: ${failed_hosts[*]}"
    log_error "手動確認: LINUX_SETUP_EXPOSE_BECOME_PASSWORD=1 ansible all -i ${INVENTORY_SCRIPT} -b -m command -a true"
    for host in "${failed_hosts[@]}"; do
      log_error "詳細確認: ${host}"
      ANSIBLE_SSH_ARGS="${ansible_ssh_args}" LINUX_SETUP_EXPOSE_BECOME_PASSWORD=1 ansible "${host}" -i "${INVENTORY_SCRIPT}" -b -m command -a "true" -vvv 2>&1 | tee -a "${LOG_FILE}" || true
    done
    exit 1
  fi

  log "Ansible ping / become 確認完了"
}

######################################################################################################################################################
# check_ssh 関数
# @param  なし
# @return なし
# @error  いずれかのノードへ SSH 接続できない場合は exit 1
# @note   host 個別 key / username があれば優先し、未設定時はトップレベル設定へフォールバックする。
######################################################################################################################################################
function check_ssh() {
  log "SSH 接続確認開始"
  local failed=0

  local default_key default_user
  default_key=$(yq eval '.key' "${SETTINGS_FILE}")
  default_user=$(yq eval '.username' "${SETTINGS_FILE}")

  for group in control_plane workers proxmox; do
    local count
    count=$(yq eval ".nodes.${group} | length" "${SETTINGS_FILE}" 2>/dev/null || echo 0)
    [[ "${count}" == "null" || -z "${count}" || "${count}" == "0" ]] && continue
    for i in $(seq 0 $((count - 1))); do
      local ip host_user host_key
      ip=$(yq eval ".nodes.${group}[${i}].ip" "${SETTINGS_FILE}" 2>/dev/null || true)
      [[ "${ip}" == "null" || -z "${ip}" ]] && continue
      host_user=$(yq eval ".nodes.${group}[${i}].username // \"\"" "${SETTINGS_FILE}" 2>/dev/null || true)
      host_key=$(yq eval  ".nodes.${group}[${i}].key // \"\"" "${SETTINGS_FILE}" 2>/dev/null || true)
      [[ -z "${host_user}" ]] && host_user="${default_user}"
      [[ -z "${host_key}" ]]  && host_key="${default_key}"
      host_key="${host_key/#\~/${HOME}}"

      if [[ ! -f "${host_key}" ]]; then
        log_error "SSH 秘密鍵が見つかりません: ${host_key} (${host_user}@${ip})"
        failed=1
        continue
      fi

      if ! ssh -F /dev/null -i "${host_key}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
          -o BatchMode=yes "${host_user}@${ip}" "exit" &>/dev/null; then
        log_error "SSH 接続失敗: ${host_user}@${ip}"
        failed=1
      else
        log "SSH 接続 OK: ${host_user}@${ip}"
      fi
    done
  done

  if [[ ${failed} -eq 1 ]]; then
    log_error "SSH 接続確認失敗。接続できないノードがあります。"
    exit 1
  fi

  log "SSH 接続確認完了"
}
