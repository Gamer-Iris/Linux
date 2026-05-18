#!/bin/bash

######################################################################################################################################################
# ファイル   : validation.sh
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

# setup.sh 実行前の静的な前提条件チェックを担当する。ファイル存在、権限、role 実装状況のみ確認する。

######################################################################################################################################################
# check_prerequisites 関数
# @param  なし
# @return なし
# @error  必須コマンドが不足している場合は exit 1
# @note   setup.sh は k8s control-plane 上で実行する想定のため、Ansible / ssh / yq もここで確認する。
######################################################################################################################################################
function check_prerequisites() {
  log "前提条件チェック開始"
  local missing=0
  local -a missing_cmds=()

  for cmd in bash python3 yq jq kubeseal ansible ansible-playbook ansible-inventory ssh curl wget tmux; do
    if ! command -v "${cmd}" &>/dev/null; then
      missing_cmds+=("${cmd}")
      missing=1
    fi
  done

  if [[ ${missing} -eq 1 ]]; then
    log_error "前提条件チェック失敗。不足コマンド: ${missing_cmds[*]}"
    log_error "k8s control-plane 上で platforms/setup/bootstrap.sh を実行してから再実行してください。"
    exit 1
  fi

  log "前提条件チェック完了"
}

######################################################################################################################################################
# check_not_root 関数
# @param  なし
# @return なし
# @error  root 実行の場合は exit 1
# @note   必要な昇格は Ansible の become に限定し、setup.sh 自体は通常ユーザーで実行する。
######################################################################################################################################################
function check_not_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    log_error "setup.sh は root ではなく、SSH / sudo 可能な通常ユーザーで実行してください。"
    log_error "Ansible 側で必要な処理だけ become: true により sudo 実行します。"
    exit 1
  fi
}

######################################################################################################################################################
# check_settings 関数
# @param  なし
# @return なし
# @error  settings_secret.yml 未配置、権限不備、プレースホルダー残存、control_plane 未設定時は exit 1
# @note   secret の値そのものはログ出力しない。
######################################################################################################################################################
function check_settings() {
  log "settings_secret.yml チェック開始"

  if [[ ! -f "${SETTINGS_FILE}" ]]; then
    log_error "settings_secret.yml が見つかりません: ${SETTINGS_FILE}"
    log_error "以下を実行し、すべてのプレースホルダーを実値に編集してください。"
    log_error "  cp ${REPO_ROOT}/platforms/settings/settings_secret_template.yml ${SETTINGS_FILE}"
    log_error "  nano ${SETTINGS_FILE}"
    log_error "README.md の「settings_secret.yml 準備」と「環境構築手順（自動構築）」を参照してください。"
    exit 1
  fi

  local settings_perm
  settings_perm=$(stat -c '%a' "${SETTINGS_FILE}" 2>/dev/null || stat -f '%Lp' "${SETTINGS_FILE}" 2>/dev/null || echo "")
  if [[ -n "${settings_perm}" && "${settings_perm}" != "600" ]]; then
    log_error "settings_secret.yml の権限が安全ではありません: ${settings_perm}"
    log_error "以下を実行してください: chmod 600 ${SETTINGS_FILE}"
    exit 1
  fi

  if grep -q "ご自分の環境に合わせてください。" "${SETTINGS_FILE}"; then
    log_error "settings_secret.yml にプレースホルダーが残っています。すべての項目を実際の値に書き換えてください。"
    log_error "対象ファイル: ${SETTINGS_FILE}"
    exit 1
  fi

  local cp_count
  cp_count=$(yq eval '.nodes.control_plane | length' "${SETTINGS_FILE}" 2>/dev/null || echo 0)
  if [[ "${cp_count}" == "null" || -z "${cp_count}" || "${cp_count}" == "0" ]]; then
    log_error "settings_secret.yml の nodes.control_plane が空です。k8s control-plane の ip / username を設定してください。"
    exit 1
  fi

  log "settings_secret.yml チェック完了"
}

######################################################################################################################################################
# check_argocd_key 関数
# @param  なし
# @return なし
# @error  Deploy Key パス未設定、秘密鍵未配置、権限不備の場合は exit 1
# @note   control-plane / all 実行時に必要な GitOps 連携の前提を確認する。
######################################################################################################################################################
function check_argocd_key() {
  log "ArgoCD Deploy Key チェック開始"

  local deploy_key_path
  deploy_key_path=$(yq eval '.argocd.deploy_key_path // ""' "${SETTINGS_FILE}")
  if [[ -z "${deploy_key_path}" || "${deploy_key_path}" == "null" ]]; then
    log_error "settings_secret.yml の argocd.deploy_key_path が未設定です。"
    log_error "README.md の「Argo CD 事前準備」を参照し、Deploy Key 秘密鍵パスを設定してください。"
    exit 1
  fi

  deploy_key_path="${deploy_key_path/#\~/${HOME}}"
  if [[ ! -f "${deploy_key_path}" ]]; then
    log_error "ArgoCD Deploy Key 秘密鍵が見つかりません: ${deploy_key_path}"
    log_error "README.md の「Argo CD 事前準備」に従い ssh-keygen で鍵を作成し、公開鍵を GitHub Deploy Key に登録してください。"
    exit 1
  fi

  local deploy_key_perm
  deploy_key_perm=$(stat -c '%a' "${deploy_key_path}" 2>/dev/null || stat -f '%Lp' "${deploy_key_path}" 2>/dev/null || echo "")
  if [[ -n "${deploy_key_perm}" && "${deploy_key_perm}" != "600" ]]; then
    log_error "ArgoCD Deploy Key 秘密鍵の権限が安全ではありません: ${deploy_key_perm}"
    log_error "以下を実行してください: chmod 600 ${deploy_key_path}"
    exit 1
  fi

  log "ArgoCD Deploy Key チェック完了"
}

######################################################################################################################################################
# check_rook_env 関数
# @param  なし
# @return なし
# @error  rook-ceph-env.sh 未配置または権限不備の場合は exit 1
# @note   --skip-manual 指定時は、手動 import を意図的に後回しにする運用としてスキップする。
######################################################################################################################################################
function check_rook_env() {
  if [[ ${SKIP_MANUAL} -eq 1 ]]; then
    log "rook-ceph-env.sh チェックをスキップ（--skip-manual 指定）"
    return
  fi

  log "rook-ceph-env.sh チェック開始"

  if [[ ! -f "${ROOK_ENV_FILE}" ]]; then
    log_error "rook-ceph-env.sh が見つかりません: ${ROOK_ENV_FILE}"
    log_error "Proxmox 側で Rook external cluster import を実行し、出力された export 文をこのファイルに保存してください。"
    log_error "README.md の「Rook external cluster import」と「環境構築手順（自動構築）」を参照してください。"
    exit 1
  fi

  local rook_env_perm
  rook_env_perm=$(stat -c '%a' "${ROOK_ENV_FILE}" 2>/dev/null || stat -f '%Lp' "${ROOK_ENV_FILE}" 2>/dev/null || echo "")
  if [[ -n "${rook_env_perm}" && "${rook_env_perm}" != "600" ]]; then
    log_error "rook-ceph-env.sh の権限が安全ではありません: ${rook_env_perm}"
    log_error "以下を実行してください: chmod 600 ${ROOK_ENV_FILE}"
    exit 1
  fi

  log "rook-ceph-env.sh チェック完了"
}

######################################################################################################################################################
# check_roles 関数
# @param  なし
# @return なし
# @error  MODE に対応する role/tasks/main.yml が存在しない場合は exit 1
# @note   Ansible 実行前に未実装 role を検出し、途中失敗を避ける。
######################################################################################################################################################
function check_roles() {
  log "role 実装状況チェック開始"
  local missing=0

  local -a roles_to_check=()
  case "${MODE}" in
    all)           roles_to_check=(common control_plane workers node_config) ;;
    common)        roles_to_check=(common) ;;
    control-plane) roles_to_check=(control_plane) ;;
    secrets)       roles_to_check=(control_plane) ;;
    workers)       roles_to_check=(workers) ;;
    node-config)   roles_to_check=(node_config) ;;
  esac

  for role in "${roles_to_check[@]}"; do
    if [[ ! -f "${SCRIPT_DIR}/roles/${role}/tasks/main.yml" ]]; then
      log_error "role が未実装: ${role} (roles/${role}/tasks/main.yml が存在しません)"
      missing=1
    fi
  done

  if [[ ${missing} -eq 1 ]]; then
    log_error "未実装 role があります。〜3 の実装が完了してから再実行してください。"
    exit 1
  fi

  log "role 実装状況チェック完了"
}
