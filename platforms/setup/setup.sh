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
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
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
PUBLISH_RELEASE=1
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
  --publish, --release all では既定で有効（後方互換のため指定可）
  --skip-manual        Rook 等の手動介入ステップをスキップ
  --tags TAGS          ansible-playbook --tags に渡す
  --start-at TASK      ansible-playbook --start-at-task に渡す
  --limit PATTERN      ansible-playbook --limit に渡す（特定ノードのみ実行）
  -h, --help           このヘルプを表示

NOTE:
  all の本実行完了後、GreetMate JAR の GitHub Release 登録 workflow を起動します。
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
    read -r -p "SealedSecret manifest を git commit/push し、secrets Application を sync しますか？ [yes/NO]: " answer
    if [[ "${answer}" != "yes" ]]; then
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
# @error  GitHub CLI 未導入 / 未認証 / workflow dispatch 失敗時 return 1
# @note   setup.sh all 完了後に GreetMate JAR の build / artifact upload / GitHub Release 作成 workflow を起動する。
######################################################################################################################################################
function publish_greetmate_release() {
  local output=""

  if [[ "${MODE}" != "all" ]]; then
    return 0
  fi

  if [[ ${DRY_RUN} -eq 1 ]]; then
    log "GreetMate Release workflow dispatch をスキップします（--dry-run 指定）"
    return 0
  fi

  if [[ ${PUBLISH_RELEASE} -ne 1 ]]; then
    log "GreetMate Release workflow dispatch をスキップします（--no-publish 指定）"
    return 0
  fi

  log "GreetMate JAR の GitHub Release 登録 workflow を起動します"
  log "workflow: build-release.yml, ref: main, deploy_to_servers=false（deploy は実行しません）"

  if ! command -v gh >/dev/null 2>&1; then
    log_error "GreetMate JAR の Release 登録には GitHub CLI gh が必要です。"
    log_error "GitHub CLI をインストールし、gh auth login で認証してから再実行してください。"
    return 1
  fi

  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    log_error "GitHub CLI が github.com に認証されていません。"
    log_error "gh auth login を実行し、Gamer-Iris/Linux の Actions workflow 実行権限を持つアカウントで認証してください。"
    return 1
  fi

  if ! output="$(gh workflow view build-release.yml --repo Gamer-Iris/Linux 2>&1)"; then
    log_error "build-release.yml を参照できません。リポジトリ権限または workflow 名を確認してください。"
    log_error "${output}"
    return 1
  fi

  if ! output="$(gh workflow run build-release.yml --repo Gamer-Iris/Linux --ref main -f deploy_to_servers=false 2>&1)"; then
    log_error "build-release.yml の workflow dispatch に失敗しました。"
    log_error "Gamer-Iris/Linux の Actions 実行権限、workflow_dispatch の有効状態、ref=main を確認してください。"
    log_error "${output}"
    return 1
  fi

  if [[ -n "${output}" ]]; then
    log "${output}"
  fi

  log "GreetMate Release workflow dispatch 完了"
  log "実行状況確認: gh run list --repo Gamer-Iris/Linux --workflow build-release.yml --limit 3"
  log "成功まで待つ場合: gh run watch --repo Gamer-Iris/Linux"
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
