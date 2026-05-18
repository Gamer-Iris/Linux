#!/bin/bash

######################################################################################################################################################
# ファイル   : bootstrap.sh
# 引数       : なし
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# setup.sh 実行前に k8s control-plane 側へ必要な CLI と前提ファイルを準備する。
# secret の実値編集、Argo CD Deploy Key 登録、Rook external cluster の export 貼り付けは人が行う。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SETTINGS_FILE="${REPO_ROOT}/platforms/settings/settings_secret.yml"
SETTINGS_TEMPLATE="${REPO_ROOT}/platforms/settings/settings_secret_template.yml"
ROOK_ENV_FILE="${SCRIPT_DIR}/rook-ceph-env.sh"
ASSUME_YES=0

function usage() {
  cat <<EOF
使用方法: $(basename "$0") [OPTIONS]

OPTIONS:
  --yes       確認プロンプトを省略して必要な導入・作成・権限補正を実行する
  -h, --help  このヘルプを表示
EOF
}

function log() {
  echo "[bootstrap] $*"
}

function log_error() {
  echo "[bootstrap][ERROR] $*" >&2
}

function require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_error "必要なコマンドが見つかりません: ${cmd}"
    exit 1
  fi
}

function confirm() {
  local message="$1"

  if [[ ${ASSUME_YES} -eq 1 ]]; then
    log "${message}: yes (--yes)"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    log_error "非対話実行では確認できません: ${message}"
    log_error "自動実行する場合は --yes を指定してください"
    return 1
  fi

  local answer
  while true; do
    read -r -p "${message} [y/N]: " answer
    case "${answer}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|"") return 1 ;;
      *) echo "y または n を入力してください。" ;;
    esac
  done
}

function install_apt_packages() {
  local -a packages=(python3 python3-pip ansible curl wget jq tar openssh-client tmux)
  local -a missing=()

  for package in "${packages[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "install ok installed"; then
      missing+=("${package}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    log "apt パッケージは導入済みです"
    return
  fi

  if ! confirm "不足 apt パッケージをインストールしますか？ (${missing[*]})"; then
    log_error "不足 apt パッケージがあるため停止します: ${missing[*]}"
    exit 1
  fi

  sudo apt update
  sudo apt install -y "${missing[@]}"
}

function detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      log_error "未対応アーキテクチャです: $(uname -m)"
      exit 1
      ;;
  esac
}

function install_yq() {
  if command -v yq >/dev/null 2>&1; then
    log "yq は導入済みです: $(command -v yq)"
    return
  fi

  local arch
  arch="$(detect_arch)"
  if ! confirm "yq を /usr/local/bin/yq にインストールしますか？"; then
    log_error "yq が必要なため停止します"
    exit 1
  fi

  sudo wget "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}" -O /usr/local/bin/yq
  sudo chmod +x /usr/local/bin/yq
}

function install_kubeseal() {
  if command -v kubeseal >/dev/null 2>&1; then
    log "kubeseal は導入済みです: $(command -v kubeseal)"
    return
  fi

  local arch latest_version
  arch="$(detect_arch)"
  latest_version="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    https://github.com/bitnami-labs/sealed-secrets/releases/latest | sed 's#.*/##')"

  if [[ -z "${latest_version}" || "${latest_version}" == "latest" ]]; then
    log_error "kubeseal の最新バージョンを取得できませんでした"
    exit 1
  fi

  if ! confirm "kubeseal ${latest_version} を /usr/local/bin/kubeseal にインストールしますか？"; then
    log_error "kubeseal が必要なため停止します"
    exit 1
  fi

  (
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT
    wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/${latest_version}/kubeseal-${latest_version#v}-linux-${arch}.tar.gz" \
      -O "${tmp_dir}/kubeseal.tar.gz"
    tar -xzf "${tmp_dir}/kubeseal.tar.gz" -C "${tmp_dir}" kubeseal
    sudo install -m 0755 "${tmp_dir}/kubeseal" /usr/local/bin/kubeseal
  )
}

function prepare_settings_file() {
  if [[ -f "${SETTINGS_FILE}" ]]; then
    local settings_perm
    settings_perm=$(stat -c '%a' "${SETTINGS_FILE}" 2>/dev/null || stat -f '%Lp' "${SETTINGS_FILE}" 2>/dev/null || echo "")
    if [[ -n "${settings_perm}" && "${settings_perm}" != "600" ]]; then
      if confirm "settings_secret.yml の権限を 600 に補正しますか？ (現在: ${settings_perm})"; then
        chmod 600 "${SETTINGS_FILE}"
      else
        log_error "settings_secret.yml の権限が安全ではないため停止します"
        exit 1
      fi
    fi
    log "settings_secret.yml は作成済みです"
    return
  fi

  if [[ ! -f "${SETTINGS_TEMPLATE}" ]]; then
    log_error "settings_secret_template.yml が見つかりません: ${SETTINGS_TEMPLATE}"
    exit 1
  fi

  if ! confirm "settings_secret.yml をテンプレートから作成しますか？"; then
    log_error "settings_secret.yml が必要なため停止します"
    exit 1
  fi

  cp "${SETTINGS_TEMPLATE}" "${SETTINGS_FILE}"
  chmod 600 "${SETTINGS_FILE}"
  log "settings_secret.yml をテンプレートから作成しました: ${SETTINGS_FILE}"
  log "この後、プレースホルダーを実値に編集してください"
}

function normalize_secret_permissions() {
  if [[ -f "${ROOK_ENV_FILE}" ]]; then
    local rook_env_perm
    rook_env_perm=$(stat -c '%a' "${ROOK_ENV_FILE}" 2>/dev/null || stat -f '%Lp' "${ROOK_ENV_FILE}" 2>/dev/null || echo "")
    if [[ -n "${rook_env_perm}" && "${rook_env_perm}" != "600" ]]; then
      if confirm "rook-ceph-env.sh の権限を 600 に補正しますか？ (現在: ${rook_env_perm})"; then
        chmod 600 "${ROOK_ENV_FILE}"
      else
        log_error "rook-ceph-env.sh の権限が安全ではないため停止します"
        exit 1
      fi
    fi
    log "rook-ceph-env.sh は作成済みです"
  else
    log "rook-ceph-env.sh は未作成です。Rook external cluster import 後に作成してください"
  fi

  if [[ -f "${SETTINGS_FILE}" ]] && command -v yq >/dev/null 2>&1; then
    local deploy_key_path
    deploy_key_path="$(yq eval '.argocd.deploy_key_path // ""' "${SETTINGS_FILE}" 2>/dev/null || true)"
    deploy_key_path="${deploy_key_path/#\~/${HOME}}"

    if [[ -n "${deploy_key_path}" && "${deploy_key_path}" != "null" && -f "${deploy_key_path}" ]]; then
      local deploy_key_perm
      deploy_key_perm=$(stat -c '%a' "${deploy_key_path}" 2>/dev/null || stat -f '%Lp' "${deploy_key_path}" 2>/dev/null || echo "")
      if [[ -n "${deploy_key_perm}" && "${deploy_key_perm}" != "600" ]]; then
        if confirm "Argo CD Deploy Key の権限を 600 に補正しますか？ (${deploy_key_path}, 現在: ${deploy_key_perm})"; then
          chmod 600 "${deploy_key_path}"
        else
          log_error "Argo CD Deploy Key の権限が安全ではないため停止します"
          exit 1
        fi
      fi
      log "Argo CD Deploy Key は配置済みです: ${deploy_key_path}"
    fi
  fi
}

function print_versions() {
  log "導入コマンド確認"
  for cmd in bash python3 yq jq kubeseal ansible ansible-playbook ansible-inventory ssh curl wget tmux; do
    require_command "${cmd}"
    echo "OK ${cmd}: $(command -v "${cmd}")"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "不明な引数: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -eq 0 ]]; then
  log_error "root ではなく、sudo 可能な通常ユーザーで実行してください"
  exit 1
fi

install_apt_packages
install_yq
install_kubeseal
prepare_settings_file
normalize_secret_permissions
print_versions

log "bootstrap 完了"
log "次に settings_secret.yml の実値編集、Argo CD Deploy Key 作成、rook-ceph-env.sh 作成を行い、./setup.sh --precheck を実行してください"
