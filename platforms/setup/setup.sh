#!/bin/bash

######################################################################################################################################################
# ファイル   : setup.sh
# 引数       : MODE [OPTIONS]
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#            : 10（異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# setup.sh は環境構築の入口として実行順序だけを制御し、実処理は lib/*.sh に分離する。

#*****************************************************************************************************************************************************
# 定数エリア
#*****************************************************************************************************************************************************
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SETTINGS_FILE="${REPO_ROOT}/platforms/settings/settings_secret.yml"
ROOK_ENV_FILE="${SCRIPT_DIR}/rook-ceph-env.sh"
INVENTORY_SCRIPT="${SCRIPT_DIR}/inventory.sh"
SITE_YML="${SCRIPT_DIR}/site.yml"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/setup_$(date '+%Y%m%d_%H%M%S').log"
ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-${USER}/tmp}"
export ANSIBLE_LOCAL_TEMP
ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-${SCRIPT_DIR}/ansible.cfg}"
export ANSIBLE_CONFIG

#*****************************************************************************************************************************************************
# 変数エリア
#*****************************************************************************************************************************************************
MODE=""
DRY_RUN=0
SKIP_MANUAL=0
PRECHECK=0
ASSUME_YES=0
PUBLISH_RELEASE=auto
ANSIBLE_TAGS=""
ANSIBLE_START_AT=""
ANSIBLE_LIMIT=""

#*****************************************************************************************************************************************************
# 共通ライブラリ
#*****************************************************************************************************************************************************
# shellcheck source=platforms/setup/lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=platforms/setup/lib/confirm.sh
source "${SCRIPT_DIR}/lib/confirm.sh"
# shellcheck source=platforms/setup/lib/validation.sh
source "${SCRIPT_DIR}/lib/validation.sh"
# shellcheck source=platforms/setup/lib/inventory_checks.sh
source "${SCRIPT_DIR}/lib/inventory_checks.sh"
# shellcheck source=platforms/setup/lib/ansible_runner.sh
source "${SCRIPT_DIR}/lib/ansible_runner.sh"

######################################################################################################################################################
# usage 関数
# @param  なし
# @return なし
# @note   setup.sh の利用方法を標準出力へ表示する。
######################################################################################################################################################
function usage() {
  cat <<EOF
使用方法: $(basename "$0") MODE [OPTIONS]

MODE:
  all            全ステップを実行
  common         全ノードへ共通ミドルウェアをインストール
  control-plane  コントロールプレーン初期化・アプリデプロイ
  secrets        Argo CD / sealed-secrets 準備と SealedSecret 生成・Git 反映を実行
  workers        ワーカーノードを k8s クラスタへ参加
  node-config    全ノードの crontab / logrotate 設定

OPTIONS:
  --dry-run            Ansible を --check モードで実行（変更なし）
  --precheck           前提条件 / inventory / SSH / Ansible ping のみ確認して終了
  --yes                破壊的になり得る本実行の確認プロンプトを省略
  --no-publish         all 完了後の GreetMate GitHub Release 登録 workflow 起動をスキップ
  --publish, --release all 完了後の GreetMate GitHub Release 登録 workflow 起動を強制
  --skip-manual        Rook 等の手動介入ステップをスキップ
  --tags TAGS          ansible-playbook --tags に渡す
  --start-at TASK      ansible-playbook --start-at-task に渡す
  --limit PATTERN      ansible-playbook --limit に渡す（特定ノードのみ実行）
  -h, --help           このヘルプを表示

NOTE:
  all の本実行完了後、github.dispatch_build_release=true の場合のみ GreetMate JAR の GitHub Release 登録 workflow を起動します。
  all --publish を指定した場合は github.dispatch_build_release に関係なく workflow を起動します。
  all --no-publish を指定した場合は workflow を起動しません。
  deploy_to_servers=false で起動するため、Minecraft サーバーへの deploy は実行しません。
EOF
}

######################################################################################################################################################
# require_option_value 関数
# @param  $1 : オプション名
# @param  $2 : オプション値
# @return なし
# @error  値が空、または次のオプションに見える場合は exit 1
# @note   set -u による分かりにくい異常終了を避けるため、引数パース時に明示チェックする。
######################################################################################################################################################
function require_option_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" || "${value}" == --* ]]; then
    echo "${option} には値が必要です。" >&2
    usage
    exit 1
  fi
}

######################################################################################################################################################
# resolve_path 関数
# @param  $1 : path
# @return 正規化した絶対 path を標準出力
# @error  realpath / Python のいずれも利用できない場合 exit 1
# @note   GNU realpath -m が無い環境では Python で path 正規化を行う。
######################################################################################################################################################
function resolve_path() {
  local target_path="$1"

  if realpath -m -- "${target_path}" >/dev/null 2>&1; then
    realpath -m -- "${target_path}"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os, sys; print(os.path.abspath(os.path.normpath(sys.argv[1])))' "${target_path}"
    return
  fi

  if command -v python >/dev/null 2>&1; then
    python -c 'import os, sys; print(os.path.abspath(os.path.normpath(sys.argv[1])))' "${target_path}"
    return
  fi

  echo "ERROR: realpath -m または Python が必要です: ${target_path}" >&2
  exit 1
}

######################################################################################################################################################
# validate_generated_staged_paths 関数
# @param  $1 : SealedSecret manifest directory
# @return なし
# @error  staged に許可外 path / symlink / 不正な path 表現が含まれる場合 exit 1
# @note   setup.sh secrets の自動 commit 対象を SealedSecret manifest だけに限定する。
######################################################################################################################################################
function validate_generated_staged_paths() {
  local secrets_path="$1"
  local resolved_secrets_path=""
  local staged_file=""
  local resolved_staged_file=""
  local staged_mode=""

  resolved_secrets_path="$(resolve_path "${REPO_ROOT}/${secrets_path}")"

  while IFS= read -r -d '' staged_file; do
    if [[ -z "${staged_file}" || "${staged_file}" == *$'\r'* || "${staged_file}" == ../* || "${staged_file}" == */../* || "${staged_file}" == */.. ]]; then
      echo "ERROR: staged に安全でない path が含まれています: ${staged_file}" >&2
      git diff --cached --name-status -- . >&2
      exit 1
    fi

    resolved_staged_file="$(resolve_path "${REPO_ROOT}/${staged_file}")"
    case "${resolved_staged_file}" in
      "${resolved_secrets_path}"/*) ;;
      *)
        echo "ERROR: staged に ${secrets_path} 以外の変更があります。" >&2
        git diff --cached --name-status -- . >&2
        exit 1
        ;;
    esac

    staged_mode="$(git ls-files -s -- "${staged_file}" | awk 'NR==1 {print $1}')"
    if [[ "${staged_mode}" == "120000" || -L "${REPO_ROOT}/${staged_file}" ]]; then
      echo "ERROR: setup.sh secrets の自動 commit 対象に symbolic link は含められません: ${staged_file}" >&2
      git diff --cached --name-status -- . >&2
      exit 1
    fi
  done < <(git diff --cached --name-only --relative -z -- .)
}

######################################################################################################################################################
# finalize_secrets_mode 関数
# @param  なし
# @return なし
# @note   setup.sh secrets 後に SealedSecret manifest の差分を表示し、
#         承認時のみ Git 反映と Argo CD sync を行う。
######################################################################################################################################################
function finalize_secrets_mode() {
  local secrets_path="platforms/kubernetes/apps/secrets"
  local generated_paths=("${secrets_path}")
  local app_file="platforms/kubernetes/argo-cd-apps-deployment3.yml"
  local github_ssh_key_path=""
  local github_ssh_key_perm=""
  local changed=0

  if [[ "${MODE}" != "secrets" || ${DRY_RUN} -eq 1 || ${PRECHECK} -eq 1 ]]; then
    return
  fi

  log "SealedSecret manifest 差分確認開始"
  (
    cd "${REPO_ROOT}"
    git status --short -- "${generated_paths[@]}"
    git --no-pager diff -- "${generated_paths[@]}"
  ) | tee -a "${LOG_FILE}"

  if [[ -n "$(cd "${REPO_ROOT}" && git status --porcelain -- "${generated_paths[@]}")" ]]; then
    changed=1
    log "git status の '??' は未追跡ファイルを表します。setup.sh secrets が生成した SealedSecret manifest 候補で、承認すると Git add / commit / push 対象になります。"
  fi

  if [[ ${ASSUME_YES} -eq 1 ]]; then
    log "--yes 指定により SealedSecret manifest の Git 反映と secrets sync を実行します"
  else
    if [[ ! -t 0 ]]; then
      log_error "非対話実行で commit/push/sync まで行う場合は --yes が必要です。生成済み差分を確認して手動反映してください。"
      log "手動反映例: git add ${secrets_path} && git commit -m \"Update sealed app secrets\" && git push && kubectl apply -f ${app_file} && argocd app sync secrets"
      return
    fi
    local answer
    read -r -p "SealedSecret manifest を git commit/push し、secrets Application を sync しますか？ [y/N]: " answer
    if [[ "${answer}" != "y" ]]; then
      log "SealedSecret manifest の生成のみで停止します。差分確認後、必要に応じて手動で commit/push/sync してください。"
      log "手動反映例: git add ${secrets_path} && git commit -m \"Update sealed app secrets\" && git push && kubectl apply -f ${app_file} && argocd app sync secrets"
      return
    fi
  fi

  log "SealedSecret 自動反映の Git 状態を検査します"
  (
    cd "${REPO_ROOT}"

    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || {
      echo "ERROR: upstream が未設定のため、自動 push/sync は実行しません。" >&2
      exit 1
    }

    ahead_count=$(git rev-list --count "${upstream}..HEAD")
    if [[ "${ahead_count}" != "0" ]]; then
      echo "ERROR: 実行前から未push commit が ${ahead_count} 件あります。" >&2
      echo "ERROR: setup.sh secrets は生成した SealedSecret manifest commit だけを push できる状態でのみ自動反映します。" >&2
      git --no-pager log --oneline "${upstream}..HEAD" >&2
      exit 1
    fi

    validate_generated_staged_paths "${secrets_path}"
  ) 2>&1 | tee -a "${LOG_FILE}"

  github_ssh_key_path=$(yq eval '.github.ssh_key_path // ""' "${SETTINGS_FILE}")
  if [[ -z "${github_ssh_key_path}" || "${github_ssh_key_path}" == "null" ]]; then
    log_error "settings_secret.yml の github.ssh_key_path が未設定です。"
    log_error "setup.sh secrets の自動 commit/push には GitHub push 用 SSH 秘密鍵パスが必要です。"
    exit 1
  fi
  github_ssh_key_path="${github_ssh_key_path/#\~/${HOME}}"
  if [[ ! -f "${github_ssh_key_path}" ]]; then
    log_error "GitHub push 用 SSH 秘密鍵が見つかりません: ${github_ssh_key_path}"
    exit 1
  fi
  github_ssh_key_perm=$(stat -c '%a' "${github_ssh_key_path}" 2>/dev/null || stat -f '%Lp' "${github_ssh_key_path}" 2>/dev/null || echo "")
  if [[ -n "${github_ssh_key_perm}" && "${github_ssh_key_perm}" != "600" ]]; then
    log_error "GitHub push 用 SSH 秘密鍵の権限が安全ではありません: ${github_ssh_key_perm}"
    log_error "以下を実行してください: chmod 600 ${github_ssh_key_path}"
    exit 1
  fi

  if [[ ${changed} -eq 1 ]]; then
    log "SealedSecret manifest を Git commit / push します"
    (
      cd "${REPO_ROOT}"
      git add "${secrets_path}"
      if git diff --cached --quiet -- "${generated_paths[@]}"; then
        echo "No staged SealedSecret manifest changes. Skip commit/push."
      else
        validate_generated_staged_paths "${secrets_path}"
        echo "Auto push target files:"
        git diff --cached --name-status -- "${generated_paths[@]}"
        git commit -m "Update sealed app secrets"
        GIT_SSH_COMMAND="ssh -F /dev/null -i ${github_ssh_key_path} -o UserKnownHostsFile=${HOME}/.ssh/known_hosts" git push
      fi
    ) 2>&1 | tee -a "${LOG_FILE}"
  else
    log "SealedSecret manifest に差分がないため commit/push をスキップします"
  fi

  log "secrets Application を作成 / sync します"
  (
    cd "${REPO_ROOT}"
    kubectl apply -f "${app_file}"
    argocd app sync secrets
  ) 2>&1 | tee -a "${LOG_FILE}"
  log "secrets Application sync 完了"
}

######################################################################################################################################################
# publish_greetmate_release 関数
# @param  なし
# @return なし
# @error  GitHub workflow API 参照 / dispatch 失敗時 return 1
# @note   setup.sh all 完了後に GreetMate JAR の build / artifact upload / GitHub Release 作成 workflow を起動する。
######################################################################################################################################################
function publish_greetmate_release() {
  if [[ "${MODE}" != "all" ]]; then
    return 0
  fi

  if [[ ${DRY_RUN} -eq 1 ]]; then
    log "GreetMate Release workflow dispatch をスキップします（--dry-run 指定）"
    return 0
  fi

  if [[ "${PUBLISH_RELEASE}" == "0" ]]; then
    log "GreetMate Release workflow dispatch をスキップします（--no-publish 指定）"
    return 0
  fi

  local dispatch_build_release
  dispatch_build_release=$(yq eval '.github.dispatch_build_release // false' "${SETTINGS_FILE}")
  if [[ "${PUBLISH_RELEASE}" == "auto" && "${dispatch_build_release}" != "true" ]]; then
    log "GreetMate Release workflow dispatch をスキップします（github.dispatch_build_release=false）"
    return 0
  fi

  local github_enabled owner repo token workflow_id workflow_ref
  github_enabled=$(yq eval '.github.enabled // false' "${SETTINGS_FILE}")
  owner=$(yq eval '.github.owner // ""' "${SETTINGS_FILE}")
  repo=$(yq eval '.github.repo // ""' "${SETTINGS_FILE}")
  token=$(yq eval '.github.token // ""' "${SETTINGS_FILE}")
  workflow_id=$(yq eval '.github.build_release_workflow // "build-release.yml"' "${SETTINGS_FILE}")
  workflow_ref=$(yq eval '.github.build_release_ref // "main"' "${SETTINGS_FILE}")

  if [[ "${PUBLISH_RELEASE}" == "auto" && "${github_enabled}" != "true" ]]; then
    log "GreetMate Release workflow dispatch をスキップします（github.enabled=false）"
    return 0
  fi

  if [[ -z "${owner}" || "${owner}" == "null" || -z "${repo}" || "${repo}" == "null" || -z "${token}" || "${token}" == "null" ]]; then
    log_error "GreetMate Release workflow dispatch には settings_secret.yml の github.owner / github.repo / github.token が必要です。"
    log_error "token 文字列はログやチャットへ貼らないでください。"
    return 1
  fi

  log "GreetMate JAR の GitHub Release 登録 workflow を起動します"
  log "workflow: ${workflow_id}, ref: ${workflow_ref}, deploy_to_servers=false（deploy は実行しません）"

  local curl_config=""
  local previous_exit_trap previous_int_trap previous_term_trap
  previous_exit_trap=$(trap -p EXIT || true)
  previous_int_trap=$(trap -p INT || true)
  previous_term_trap=$(trap -p TERM || true)

  function cleanup_greetmate_release_curl_config() {
    if [[ -n "${curl_config:-}" ]]; then
      rm -f "${curl_config}"
      curl_config=""
    fi
  }

  function restore_greetmate_release_traps() {
    cleanup_greetmate_release_curl_config
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

  function abort_greetmate_release_dispatch() {
    local rc="$1"
    trap - EXIT INT TERM
    cleanup_greetmate_release_curl_config
    exit "${rc}"
  }

  function greetmate_release_status_hint() {
    case "$1" in
      401) echo "token が無効、期限切れ、または認証形式が不正です。" ;;
      403) echo "token の repository 権限不足、SSO 未承認、rate limit などの可能性があります。" ;;
      404) echo "workflow が存在しない、repository access 不足、または github.owner / github.repo の誤りです。" ;;
      000) echo "network / DNS / TLS / curl 実行に失敗しました。" ;;
      *) echo "GitHub API が想定外の status を返しました。" ;;
    esac
  }

  trap 'abort_greetmate_release_dispatch 1' EXIT
  trap 'abort_greetmate_release_dispatch 130' INT
  trap 'abort_greetmate_release_dispatch 143' TERM

  curl_config="$(mktemp)"
  chmod 600 "${curl_config}"
  {
    printf '%s\n' 'silent'
    printf '%s\n' 'show-error'
    printf '%s\n' 'location'
    printf '%s\n' 'output = /dev/null'
    printf '%s\n' 'write-out = "%{http_code}"'
    printf '%s\n' 'header = "Accept: application/vnd.github+json"'
    printf '%s\n' 'header = "Content-Type: application/json"'
    printf '%s\n' "header = \"Authorization: Bearer ${token}\""
    printf '%s\n' 'header = "X-GitHub-Api-Version: 2022-11-28"'
  } > "${curl_config}"

  local workflow_url status
  workflow_url="https://api.github.com/repos/${owner}/${repo}/actions/workflows/${workflow_id}"

  status=$(curl --config "${curl_config}" "${workflow_url}" 2>/dev/null || true)
  status="${status:-000}"
  if [[ "${status}" != "200" ]]; then
    log_error "GreetMate Release workflow の参照に失敗しました。$(greetmate_release_status_hint "${status}") status=${status}"
    log_error "github.dispatch_build_release=true または --publish の場合は対象 repository の Actions: Read 権限が必要です。"
    log_error "settings_secret.yml の github.owner / github.repo / github.token と token の repository access を確認してください。"
    log_error "token 文字列はログやチャットへ貼らないでください。"
    restore_greetmate_release_traps
    return 1
  fi

  local body
  body=$(printf '{"ref":"%s","inputs":{"deploy_to_servers":"false"}}' "${workflow_ref}")
  status=$(curl --config "${curl_config}" -X POST "${workflow_url}/dispatches" -d "${body}" 2>/dev/null || true)
  status="${status:-000}"
  case "${status}" in
    200|201|202|204) ;;
    *)
      log_error "GreetMate Release workflow dispatch に失敗しました。$(greetmate_release_status_hint "${status}") status=${status}"
      log_error "github.dispatch_build_release=true または --publish の場合は対象 repository の Actions: Read and write 権限が必要です。"
      log_error "settings_secret.yml の github.owner / github.repo / github.token と token の repository access を確認してください。"
      log_error "token 文字列はログやチャットへ貼らないでください。"
      restore_greetmate_release_traps
      return 1
      ;;
  esac

  restore_greetmate_release_traps
  log "GreetMate Release workflow dispatch 完了"
  log "実行状況は GitHub Actions の workflow runs で確認してください。"
}

######################################################################################################################################################
# main 関数
# @param  MODE [OPTIONS]
# @return なし
# @note   source 時は実行せず、検証スクリプトから関数単体を呼び出せるようにする。
######################################################################################################################################################
function main() {
  #***************************************************************************************************************************************************
  # 引数パース
  #***************************************************************************************************************************************************
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      all|common|control-plane|secrets|workers|node-config)
        if [[ -n "${MODE}" ]]; then
          echo "MODE は 1 つだけ指定してください: 既存=${MODE}, 追加=$1" >&2
          usage
          exit 1
        fi
        MODE="$1"
        shift
        ;;
      --precheck)
        PRECHECK=1
        shift
        ;;
      --yes)
        ASSUME_YES=1
        shift
        ;;
      --publish|--release)
        PUBLISH_RELEASE=1
        shift
        ;;
      --no-publish)
        PUBLISH_RELEASE=0
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --skip-manual)
        SKIP_MANUAL=1
        shift
        ;;
      --tags)
        require_option_value "$1" "${2:-}"
        ANSIBLE_TAGS="$2"
        shift 2
        ;;
      --start-at)
        require_option_value "$1" "${2:-}"
        ANSIBLE_START_AT="$2"
        shift 2
        ;;
      --limit)
        require_option_value "$1" "${2:-}"
        ANSIBLE_LIMIT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "不明な引数: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  #***************************************************************************************************************************************************
  # メイン処理
  #***************************************************************************************************************************************************
  mkdir -p "${LOG_DIR}"
  log "====== setup.sh 開始 MODE=${MODE} ======"

  if [[ -z "${MODE}" && ${PRECHECK} -eq 1 ]]; then
    MODE="all"
    log "--precheck のため MODE=all として前提確認します"
  fi

  if [[ -z "${MODE}" ]]; then
    log_error "MODE が未指定です。all / common / control-plane / secrets / workers / node-config のいずれかを指定してください。"
    usage
    exit 1
  fi

  check_prerequisites
  check_not_root
  check_settings
  check_roles
  check_inventory
  check_ssh
  check_github_api_permissions

  if [[ ${PRECHECK} -eq 1 ]]; then
    if [[ "${MODE}" == "all" || "${MODE}" == "control-plane" ]]; then
      check_argocd_key
      check_rook_env
    fi
    check_ansible_ping
    log "====== setup.sh precheck 完了。dry-run または本実行へ進めます ======"
    exit 0
  fi

  if [[ "${MODE}" == "all" || "${MODE}" == "control-plane" ]]; then
    check_argocd_key
    check_rook_env
  elif [[ "${MODE}" == "secrets" ]]; then
    check_argocd_key
    check_secrets_k8s_prerequisites
  fi

  confirm_execution
  check_collections
  run_ansible
  finalize_secrets_mode
  publish_greetmate_release

  log "====== setup.sh 完了 ======"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
