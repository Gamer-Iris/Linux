#!/bin/bash

######################################################################################################################################################
# ファイル   : ansible_runner.sh
# 引数       : なし（setup.sh から source）
# 復帰値     : 0 （正常終了）
#            : 10（異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# Ansible collections の準備と ansible-playbook 実行を担当する。
# run_ansible は対象ノードへ変更を適用し得るため、呼び出し前に precheck / confirm_execution を通す。

######################################################################################################################################################
# check_collections 関数
# @param  なし
# @return なし
# @error  ansible-galaxy collection install が失敗した場合は set -e により停止
# @note   requirements.yml がない場合は、既存環境を尊重してスキップする。
######################################################################################################################################################
function check_collections() {
  local requirements_file="${SCRIPT_DIR}/requirements.yml"

  if [[ ! -f "${requirements_file}" ]]; then
    log "requirements.yml が見つかりません。Ansible collections インストールをスキップします。"
    return
  fi

  log "Ansible collections インストール開始"
  ansible-galaxy collection install -r "${requirements_file}" --upgrade 2>&1 | tee -a "${LOG_FILE}"
  log "Ansible collections インストール完了"
}

######################################################################################################################################################
# build_ansible_opts 関数
# @param  なし
# @return ansible-playbook に渡すオプション文字列
# @note   MODE による tag 補完は run_ansible 側で行う。
#         --start-at-task は空白を含むタスク名を想定し、単一クォート付きで返す。
######################################################################################################################################################
function build_ansible_opts() {
  local opts="-i ${INVENTORY_SCRIPT}"

  if [[ ${DRY_RUN} -eq 1 ]]; then
    opts="${opts} --check"
  fi

  if [[ -n "${ANSIBLE_TAGS}" ]]; then
    opts="${opts} --tags ${ANSIBLE_TAGS}"
  fi

  if [[ -n "${ANSIBLE_START_AT}" ]]; then
    opts="${opts} --start-at-task '${ANSIBLE_START_AT}'"
  fi

  if [[ -n "${ANSIBLE_LIMIT}" ]]; then
    opts="${opts} --limit ${ANSIBLE_LIMIT}"
  fi

  echo "${opts}"
}

######################################################################################################################################################
# run_ansible 関数
# @param  なし
# @return なし
# @error  ansible-playbook が失敗した場合は exit 10
# @note   sudo password は通常 inventory に出さず、実行時だけ LINUX_SETUP_EXPOSE_BECOME_PASSWORD=1 で渡す。
######################################################################################################################################################
function run_ansible() {
  local ansible_ssh_args="-F /dev/null -C -o ControlMaster=no -o ControlPath=none -o ControlPersist=no -o StrictHostKeyChecking=no"

  if [[ -z "${ANSIBLE_TAGS}" && "${MODE}" != "all" ]]; then
    ANSIBLE_TAGS="${MODE}"
  fi

  local extra_vars="settings_file=${SETTINGS_FILE}"

  if [[ -n "${MODE}" && "${MODE}" != "all" ]]; then
    extra_vars="${extra_vars} setup_mode=${MODE}"
  fi

  if [[ ${SKIP_MANUAL} -eq 1 ]]; then
    extra_vars="${extra_vars} skip_manual=true"
  fi

  if [[ -f "${ROOK_ENV_FILE}" ]]; then
    extra_vars="${extra_vars} rook_env_file=${ROOK_ENV_FILE}"
  fi

  local opts
  opts=$(build_ansible_opts)

  log "Ansible 実行開始: ansible-playbook ${opts} -e \"${extra_vars}\" ${SITE_YML}"
  # shellcheck disable=SC2086
  set +e
  ANSIBLE_SSH_ARGS="${ansible_ssh_args}" LINUX_SETUP_EXPOSE_BECOME_PASSWORD=1 ansible-playbook ${opts} -e "${extra_vars}" "${SITE_YML}" 2>&1 | tee -a "${LOG_FILE}"
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ ${rc} -ne 0 ]]; then
    log_error "Ansible 実行失敗 (rc=${rc})"
    exit 10
  fi

  log "Ansible 実行完了"
}
