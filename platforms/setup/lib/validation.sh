#!/bin/bash

######################################################################################################################################################
# ファイル   : validation.sh
# 引数       : なし（setup.sh から source）
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
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
# check_github_api_permissions 関数
# @param  なし
# @return なし
# @error  有効化された GitHub 連携で API 到達性または参照権限が不足する場合は exit 1
# @note   token 文字列や webhook URL はログ出力しない。
######################################################################################################################################################
function check_github_api_permissions() {
  if [[ "${MODE}" != "all" && "${MODE}" != "control-plane" ]]; then
    return
  fi

  local github_enabled
  github_enabled=$(yq eval '.github.enabled // false' "${SETTINGS_FILE}")
  if [[ "${github_enabled}" != "true" ]]; then
    return
  fi

  local owner repo token webhook_enabled workflow_permission_enabled dispatch_build_release publish_release
  owner=$(yq eval '.github.owner // ""' "${SETTINGS_FILE}")
  repo=$(yq eval '.github.repo // ""' "${SETTINGS_FILE}")
  token=$(yq eval '.github.token // ""' "${SETTINGS_FILE}")
  webhook_enabled=$(yq eval '.github.webhook_enabled // false' "${SETTINGS_FILE}")
  workflow_permission_enabled=$(yq eval '.github.workflow_permission_enabled // false' "${SETTINGS_FILE}")
  dispatch_build_release=$(yq eval '.github.dispatch_build_release // false' "${SETTINGS_FILE}")
  publish_release="${PUBLISH_RELEASE:-auto}"

  if [[ -z "${owner}" || "${owner}" == "null" || -z "${repo}" || "${repo}" == "null" || -z "${token}" || "${token}" == "null" ]]; then
    log_error "github.enabled=true の場合は settings_secret.yml の github.owner / github.repo / github.token を設定してください。"
    exit 1
  fi

  local curl_config=""
  local previous_exit_trap previous_int_trap previous_term_trap
  previous_exit_trap=$(trap -p EXIT || true)
  previous_int_trap=$(trap -p INT || true)
  previous_term_trap=$(trap -p TERM || true)

  function cleanup_github_api_permissions() {
    if [[ -n "${curl_config:-}" ]]; then
      rm -f "${curl_config}"
      curl_config=""
    fi
  }

  function restore_github_api_permission_traps() {
    cleanup_github_api_permissions
    if [[ -n "${previous_exit_trap}" ]]; then
      eval "${previous_exit_trap}"
    else
      trap - EXIT
    fi
    if [[ -n "${previous_int_trap}" ]]; then
      eval "${previous_int_trap}"
    else
      trap - INT
    fi
    if [[ -n "${previous_term_trap}" ]]; then
      eval "${previous_term_trap}"
    else
      trap - TERM
    fi
  }

  function github_api_permission_abort() {
    local rc="$1"
    trap - EXIT INT TERM
    cleanup_github_api_permissions
    exit "${rc}"
  }

  function github_api_status_hint() {
    case "$1" in
      401) echo "token が無効、期限切れ、または認証形式が不正です。" ;;
      403) echo "token の repository 権限不足、SSO 未承認、rate limit などの可能性があります。" ;;
      404) echo "repository access 不足、または github.owner / github.repo の誤りです。" ;;
      000) echo "network / DNS / TLS / curl 実行に失敗しました。" ;;
      *) echo "GitHub API が想定外の status を返しました。" ;;
    esac
  }

  function fail_github_api_permission_check() {
    local context="$1"
    local status="$2"
    local required_permission="$3"
    local action_hint="${4:-}"

    log_error "${context} に失敗しました。$(github_api_status_hint "${status}") status=${status}"
    if [[ -n "${required_permission}" ]]; then
      log_error "本実行では対象 repository の ${required_permission} 権限が必要です。"
    fi
    if [[ -n "${action_hint}" ]]; then
      log_error "${action_hint}"
    fi
    log_error "settings_secret.yml の github.owner / github.repo / github.token と token の repository access を確認してください。"
    log_error "token 文字列はログやチャットへ貼らないでください。"
    github_api_permission_abort 1
  }

  trap 'github_api_permission_abort 1' EXIT
  trap 'github_api_permission_abort 130' INT
  trap 'github_api_permission_abort 143' TERM

  curl_config="$(mktemp)"
  chmod 600 "${curl_config}"
  {
    printf '%s\n' 'silent'
    printf '%s\n' 'show-error'
    printf '%s\n' 'location'
    printf '%s\n' 'output = /dev/null'
    printf '%s\n' 'write-out = "%{http_code}"'
    printf '%s\n' 'header = "Accept: application/vnd.github+json"'
    printf '%s\n' "header = \"Authorization: Bearer ${token}\""
    printf '%s\n' 'header = "X-GitHub-Api-Version: 2022-11-28"'
  } > "${curl_config}"

  local status
  status=$(curl --config "${curl_config}" "https://api.github.com/repos/${owner}/${repo}" 2>/dev/null || true)
  status="${status:-000}"
  if [[ "${status}" != "200" ]]; then
    fail_github_api_permission_check "GitHub repository API の到達性・参照権限確認" "${status}" ""
  fi

  if [[ "${webhook_enabled}" == "true" ]]; then
    status=$(curl --config "${curl_config}" "https://api.github.com/repos/${owner}/${repo}/hooks" 2>/dev/null || true)
    status="${status:-000}"
    if [[ "${status}" != "200" ]]; then
      fail_github_api_permission_check \
        "GitHub webhook API の到達性・参照権限確認" \
        "${status}" \
        "Webhooks: Read and write" \
        "webhook 自動設定を使わない場合は github.webhook_enabled=false にしてください。"
    fi
  fi

  if [[ "${workflow_permission_enabled}" == "true" ]]; then
    status=$(curl --config "${curl_config}" "https://api.github.com/repos/${owner}/${repo}/actions/permissions/workflow" 2>/dev/null || true)
    status="${status:-000}"
    if [[ "${status}" != "200" ]]; then
      fail_github_api_permission_check "GitHub Actions workflow permission API の到達性・参照権限確認" "${status}" "Administration: Read and write"
    fi
  fi

  if [[ "${publish_release}" != "0" && ( "${dispatch_build_release}" == "true" || "${publish_release}" == "1" ) ]]; then
    local workflow_id
    workflow_id=$(yq eval '.github.build_release_workflow // "build-release.yml"' "${SETTINGS_FILE}")
    status=$(curl --config "${curl_config}" "https://api.github.com/repos/${owner}/${repo}/actions/workflows/${workflow_id}" 2>/dev/null || true)
    status="${status:-000}"
    if [[ "${status}" != "200" ]]; then
      fail_github_api_permission_check "GitHub Actions workflow API の到達性・参照権限確認" "${status}" "Actions: Read and write" "--publish または github.dispatch_build_release=true の場合は workflow dispatch に Actions: Read and write 権限が必要です。"
    fi
  fi

  log "GitHub API の到達性・参照権限チェック完了"
  log "注: precheck は非破壊の GET API のみ確認します。GET が成功しても write 権限不足により本実行が失敗する可能性があります。"
  restore_github_api_permission_traps
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

######################################################################################################################################################
# check_secrets_k8s_prerequisites 関数
# @param  なし
# @return なし
# @error  secrets 実行前に k8s node の基礎コマンドが不足している場合は exit 1
# @note   all --dry-run は check mode のため実インストールを行わない。初回 secrets 前の common 本実行漏れを検出する。
######################################################################################################################################################
function check_secrets_k8s_prerequisites() {
  if [[ "${MODE}" != "secrets" || ${DRY_RUN} -eq 1 || ${PRECHECK} -eq 1 ]]; then
    return
  fi

  log "secrets 実行前 k8s node 前提チェック開始"

  local ansible_ssh_args="-F /dev/null -C -o ControlMaster=no -o ControlPath=none -o ControlPersist=no -o StrictHostKeyChecking=no"
  local prereq_output
  if ! prereq_output=$(ANSIBLE_SSH_ARGS="${ansible_ssh_args}" ansible control_plane:workers -i "${INVENTORY_SCRIPT}" -m shell -a '
set +e
missing=0
for cmd in kubeadm kubelet kubectl containerd; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "MISSING_COMMAND ${cmd}"
    missing=1
  fi
done
if ! systemctl is-active containerd >/dev/null 2>&1; then
  echo "CONTAINERD_NOT_ACTIVE"
  missing=1
fi
if command -v ufw >/dev/null 2>&1; then
  ufw_status="$(ufw status verbose 2>/dev/null || true)"
  printf "%s\n" "${ufw_status}" | grep -q "^Status: active" && echo "WARN_UFW_ACTIVE"
  printf "%s\n" "${ufw_status}" | grep -qi "routed.*deny" && echo "WARN_UFW_ROUTED_DENY"
fi
exit "${missing}"
' 2>&1); then
    log_error "初回の setup.sh secrets の前に ./setup.sh common を実行してください。all --dry-run は実インストールを行いません。"
    log_error "k8s node 前提チェック結果:"
    printf '%s\n' "${prereq_output}" | sed -e 's/^/  /' | tee -a "${LOG_FILE}" >&2
    exit 1
  fi

  if grep -q "WARN_UFW_" <<< "${prereq_output}"; then
    log "UFW が active または routed deny の k8s node があります。Calico overlay / routed traffic を許可するか、k8s node では UFW を無効化してください。"
    printf '%s\n' "${prereq_output}" | grep "WARN_UFW_" | sed -e 's/^/  /' | tee -a "${LOG_FILE}" || true
  fi

  log "secrets 実行前 k8s node 前提チェック完了"
}
