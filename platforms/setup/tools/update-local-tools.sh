#!/bin/bash

######################################################################################################################################################
# ファイル   : update-local-tools.sh
# 引数       : [--apply] [--tool NAME] [--prefix PATH] [--list]
# 復帰値     : 0 正常終了
#            : 1 異常終了
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# GitHub Releases 管理の local CLI を手動更新する。
# デフォルトは dry-run であり、--apply 指定時だけ download / install を実行する。

APPLY=0
PREFIX="/usr/local"
LIST_ONLY=0
REQUESTED_TOOLS=()
SUMMARY_ROWS=()

function usage() {
  cat <<EOF
使用方法: $(basename "$0") [OPTIONS]

OPTIONS:
  --apply        実際に download / install を実行する（省略時は dry-run）
  --tool NAME    指定 tool だけ対象にする。複数回指定可
  --prefix PATH  install prefix を指定する（既定: /usr/local）
  --list         対象 tool 一覧を表示して終了
  -h, --help     このヘルプを表示
EOF
}

function log() {
  echo "[update-local-tools] $*"
}

function log_error() {
  echo "[update-local-tools][ERROR] $*" >&2
}

function normalize_version() {
  local version="$1"
  version="${version#v}"
  version="${version#V}"
  version="${version%%+*}"
  printf '%s' "${version}"
}

function cleanup() {
  if [[ -n "${CURL_CONFIG:-}" && -f "${CURL_CONFIG}" ]]; then
    rm -f "${CURL_CONFIG}"
  fi
}

function create_curl_config() {
  CURL_CONFIG="$(mktemp)"
  chmod 600 "${CURL_CONFIG}"

  {
    printf '%s\n' 'header = "Accept: application/vnd.github+json"'
    printf '%s\n' 'header = "X-GitHub-Api-Version: 2022-11-28"'
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      printf 'header = "Authorization: Bearer %s"\n' "${GITHUB_TOKEN}"
    fi
  } > "${CURL_CONFIG}"
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

function github_release_json() {
  local repo="$1"
  curl -fsSL --config "${CURL_CONFIG}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null
}

function json_field() {
  local field="$1"
  python3 -c '
import json
import sys

field = sys.argv[1]
try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)

value = payload.get(field, "")
print(value if value is not None else "")
' "${field}"
}

function asset_url_for_tool() {
  local tool="$1"
  local arch="$2"
  python3 -c '
import json
import sys

tool = sys.argv[1]
arch = sys.argv[2]

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    raise SystemExit(0)

assets = payload.get("assets", [])

def names_matching(pred):
    return [
        asset.get("browser_download_url", "")
        for asset in assets
        if pred(asset.get("name", "")) and asset.get("browser_download_url")
    ]

if tool == "kubeseal":
    candidates = names_matching(lambda name: name.startswith("kubeseal-") and f"linux-{arch}.tar.gz" in name)
elif tool == "yq":
    exact = f"yq_linux_{arch}"
    candidates = names_matching(lambda name: name == exact)
    if not candidates:
        candidates = names_matching(lambda name: name == f"{exact}.tar.gz")
elif tool == "argocd":
    candidates = names_matching(lambda name: name == f"argocd-linux-{arch}")
elif tool == "kubeconform":
    candidates = names_matching(lambda name: name.startswith("kubeconform-linux-") and f"linux-{arch}.tar.gz" in name)
else:
    candidates = []

print(candidates[0] if candidates else "")
' "${tool}" "${arch}"
}

function local_version_for_command() {
  local command_name="$1"
  local command_path="$2"
  local allow_path_fallback="$3"
  local raw=""

  if [[ -z "${command_path}" ]]; then
    if [[ "${allow_path_fallback}" != "1" ]]; then
      printf '%s' "missing"
      return
    fi
    if ! command_path="$(command -v "${command_name}" 2>/dev/null)"; then
      printf '%s' "missing"
      return
    fi
  fi

  if [[ ! -x "${command_path}" ]]; then
    printf '%s' "missing"
    return
  fi

  case "${command_name}" in
    kubeseal)
      raw="$("${command_path}" --version 2>&1 || true)"
      ;;
    yq)
      raw="$("${command_path}" --version 2>&1 || true)"
      ;;
    argocd)
      raw="$("${command_path}" version --client --short 2>&1 || true)"
      ;;
    kubeconform)
      raw="$("${command_path}" -v 2>&1 || true)"
      ;;
    *)
      raw="$("${command_path}" --version 2>&1 || true)"
      ;;
  esac

  printf '%s' "${raw}" \
    | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' \
    | grep -Eo 'v?[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.-]+)?' \
    | head -n 1 \
    || true
}

function status_for_versions() {
  local local_version="$1"
  local latest_version="$2"
  local release_status="$3"
  local asset_status="$4"

  if [[ "${release_status}" != "ok" ]]; then
    printf '%s' "${release_status}"
    return
  fi

  if [[ "${asset_status}" != "ok" ]]; then
    printf '%s' "${asset_status}"
    return
  fi

  if [[ "${local_version}" == "missing" ]]; then
    printf '%s' "missing"
    return
  fi

  if [[ -z "${local_version}" || "${local_version}" == "unknown" || "${latest_version}" == "unknown" ]]; then
    printf '%s' "version_unknown"
    return
  fi

  if [[ "$(normalize_version "${local_version}")" == "$(normalize_version "${latest_version}")" ]]; then
    printf '%s' "current"
  else
    printf '%s' "outdated"
  fi
}

function reason_for_status() {
  local status="$1"
  local detail="$2"

  case "${status}" in
    current) printf '%s' "local matches latest" ;;
    outdated) printf '%s' "local differs from latest" ;;
    missing) printf '%s' "command not found" ;;
    version_unknown) printf '%s' "local version command failed" ;;
    api_error|asset_not_found) printf '%s' "${detail}" ;;
    *) printf '%s' "unknown status" ;;
  esac
}

function add_summary_row() {
  local tool="$1"
  local local_version="$2"
  local latest_tag="$3"
  local status="$4"
  local reason="$5"
  local install_path="$6"

  SUMMARY_ROWS+=("| ${tool} | ${local_version} | ${latest_tag} | ${status} | ${reason} | ${install_path} |")
}

function print_summary() {
  echo
  echo "| Tool | Local version | Latest tag | Status | Reason | Install path |"
  echo "|---|---|---|---|---|---|"
  for row in "${SUMMARY_ROWS[@]}"; do
    echo "${row}"
  done
}

function install_binary() {
  local source_path="$1"
  local install_path="$2"
  local install_dir
  install_dir="$(dirname "${install_path}")"

  log "install: ${source_path} -> ${install_path}"

  if [[ ! -d "${install_dir}" ]]; then
    if mkdir -p "${install_dir}" 2>/dev/null; then
      :
    else
      sudo mkdir -p "${install_dir}"
    fi
  fi

  if [[ -w "${install_dir}" ]]; then
    install -m 0755 "${source_path}" "${install_path}"
  else
    sudo install -m 0755 "${source_path}" "${install_path}"
  fi
}

function extract_binary_from_asset() {
  local tool="$1"
  local asset_path="$2"
  local work_dir="$3"
  local extract_dir="${work_dir}/extract"
  local binary_path=""

  mkdir -p "${extract_dir}"

  case "${asset_path}" in
    *.tar.gz|*.tgz)
      tar -xzf "${asset_path}" -C "${extract_dir}"
      binary_path="$(find "${extract_dir}" -type f -name "${tool}" -perm /111 | head -n 1 || true)"
      if [[ -z "${binary_path}" ]]; then
        binary_path="$(find "${extract_dir}" -type f -name "${tool}" | head -n 1 || true)"
      fi
      ;;
    *)
      binary_path="${asset_path}"
      ;;
  esac

  if [[ -z "${binary_path}" || ! -f "${binary_path}" ]]; then
    log_error "${tool} binary を asset から見つけられませんでした"
    exit 1
  fi

  chmod 755 "${binary_path}"
  printf '%s' "${binary_path}"
}

function update_tool() {
  local tool="$1"
  local repo="${TOOL_REPOS[${tool}]}"
  local command_name="${TOOL_COMMANDS[${tool}]}"
  local arch="$2"
  local install_path="${PREFIX%/}/bin/${command_name}"
  local release_json latest_tag local_version local_command_path status asset_url asset_name
  local release_status="ok"
  local asset_status="ok"
  local error_detail=""
  local reason=""
  local allow_path_fallback=0

  log "check: ${tool} (${repo})"

  if ! release_json="$(github_release_json "${repo}")"; then
    latest_tag="unknown"
    asset_url=""
    release_status="api_error"
    error_detail="GitHub API request failed; check network, rate limit, or token auth"
  else
    latest_tag="$(printf '%s' "${release_json}" | json_field tag_name)"
    if [[ -z "${latest_tag}" ]]; then
      latest_tag="unknown"
      release_status="api_error"
      error_detail="latest release response did not include tag_name"
      asset_url=""
    else
      asset_url="$(printf '%s' "${release_json}" | asset_url_for_tool "${tool}" "${arch}")"
      if [[ -z "${asset_url}" ]]; then
        asset_status="asset_not_found"
        error_detail="matching linux-${arch} asset was not found"
      fi
    fi
  fi

  if [[ -x "${install_path}" ]]; then
    local_command_path="${install_path}"
  elif [[ "${PREFIX%/}" == "/usr/local" ]]; then
    local_command_path="$(command -v "${command_name}" 2>/dev/null || true)"
    allow_path_fallback=1
  else
    local_command_path=""
  fi

  local_version="$(local_version_for_command "${command_name}" "${local_command_path}" "${allow_path_fallback}")"
  if [[ -z "${local_version}" ]]; then
    local_version="unknown"
  fi

  status="$(status_for_versions "${local_version}" "${latest_tag}" "${release_status}" "${asset_status}")"
  reason="$(reason_for_status "${status}" "${error_detail}")"
  add_summary_row "${tool}" "${local_version}" "${latest_tag}" "${status}" "${reason}" "${install_path}"
  log "status: ${tool} local=${local_version} latest=${latest_tag} status=${status} reason=${reason} install_path=${install_path}"

  if [[ "${status}" == "current" ]]; then
    log "skip: ${tool} は latest です"
    return
  fi

  if [[ "${status}" == "api_error" || "${status}" == "asset_not_found" ]]; then
    log_error "skip: ${tool}: ${reason}"
    if [[ ${APPLY} -eq 1 ]]; then
      return 1
    fi
    return 0
  fi

  asset_name="$(basename "${asset_url}")"
  if [[ ${APPLY} -eq 0 ]]; then
    log "dry-run: ${tool} ${local_version} -> ${latest_tag}"
    log "dry-run: download ${asset_name}"
    log "dry-run: install to ${install_path}"
    return
  fi

  log "apply: ${tool} ${local_version} -> ${latest_tag}"
  log "download: ${asset_name}"

  (
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT
    asset_path="${tmp_dir}/${asset_name}"

    curl -fsSL "${asset_url}" -o "${asset_path}"
    binary_path="$(extract_binary_from_asset "${command_name}" "${asset_path}" "${tmp_dir}")"
    install_binary "${binary_path}" "${install_path}"
    log "installed: ${install_path}"
  )
}

declare -a TOOL_NAMES=(
  kubeseal
  yq
  argocd
  kubeconform
)

declare -A TOOL_REPOS=(
  [kubeseal]="bitnami-labs/sealed-secrets"
  [yq]="mikefarah/yq"
  [argocd]="argoproj/argo-cd"
  [kubeconform]="yannh/kubeconform"
)

declare -A TOOL_COMMANDS=(
  [kubeseal]="kubeseal"
  [yq]="yq"
  [argocd]="argocd"
  [kubeconform]="kubeconform"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --tool)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        log_error "--tool には値が必要です"
        usage >&2
        exit 1
      fi
      REQUESTED_TOOLS+=("$2")
      shift 2
      ;;
    --prefix)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        log_error "--prefix には値が必要です"
        usage >&2
        exit 1
      fi
      PREFIX="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "不明な引数: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${LIST_ONLY} -eq 1 ]]; then
  echo "| Tool | Repository | Command |"
  echo "|---|---|---|"
  for tool in "${TOOL_NAMES[@]}"; do
    echo "| ${tool} | ${TOOL_REPOS[${tool}]} | ${TOOL_COMMANDS[${tool}]} |"
  done
  exit 0
fi

if [[ ${#REQUESTED_TOOLS[@]} -eq 0 ]]; then
  REQUESTED_TOOLS=("${TOOL_NAMES[@]}")
fi

for tool in "${REQUESTED_TOOLS[@]}"; do
  if [[ -z "${TOOL_REPOS[${tool}]:-}" ]]; then
    log_error "未対応 tool です: ${tool}"
    exit 1
  fi
done

if [[ ${APPLY} -eq 0 ]]; then
  log "dry-run mode: 実更新するには --apply を指定してください"
else
  log "apply mode: 必要に応じて download / install / sudo を実行します"
fi

trap cleanup EXIT
CURL_CONFIG=""
create_curl_config

arch="$(detect_arch)"
log "arch: ${arch}"
log "prefix: ${PREFIX}"

overall_status=0
for tool in "${REQUESTED_TOOLS[@]}"; do
  if ! update_tool "${tool}" "${arch}"; then
    overall_status=1
  fi
done

print_summary

exit "${overall_status}"
