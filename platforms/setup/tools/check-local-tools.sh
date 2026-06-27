#!/bin/bash

######################################################################################################################################################
# ファイル   : check-local-tools.sh
# 引数       : [--fail-on-outdated]
# 復帰値     : 0 正常終了
#            : 1 --fail-on-outdated 指定時に outdated / missing / version_unknown / api_error / asset_not_found がある
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# GitHub Releases 管理の local CLI について、latest と手元の version 差分を検知する。
# この script は検知専用であり、sudo install や /usr/local/bin の更新は行わない。

FAIL_ON_OUTDATED=0

function usage() {
  cat <<EOF
使用方法: $(basename "$0") [OPTIONS]

OPTIONS:
  --fail-on-outdated  outdated / missing / version_unknown / api_error / asset_not_found がある場合に exit 1
  -h, --help          このヘルプを表示
EOF
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
    *) echo "unknown" ;;
  esac
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

function latest_release_info() {
  local repo="$1"
  local tool="$2"
  local arch="$3"
  local response=""
  local tag=""
  local asset_url=""

  if ! response="$(curl -fsSL --config "${CURL_CONFIG}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)"; then
    printf 'unknown\tapi_error\tGitHub API request failed; check network, rate limit, or token auth\n'
    return
  fi

  tag="$(printf '%s' "${response}" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)

print(payload.get("tag_name", "") or "")
')"

  if [[ -z "${tag}" ]]; then
    printf 'unknown\tapi_error\tlatest release response did not include tag_name\n'
    return
  fi

  if [[ "${arch}" == "unknown" ]]; then
    printf '%s\tasset_not_found\tunsupported local architecture\n' "${tag}"
    return
  fi

  asset_url="$(printf '%s' "${response}" | asset_url_for_tool "${tool}" "${arch}")"
  if [[ -z "${asset_url}" ]]; then
    printf '%s\tasset_not_found\tmatching linux-%s asset was not found\n' "${tag}" "${arch}"
    return
  fi

  printf '%s\tok\tlatest release and asset resolved\n' "${tag}"
}

function local_version_for_command() {
  local command_name="$1"
  local raw=""

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf '%s' "missing"
    return
  fi

  case "${command_name}" in
    kubeseal)
      raw="$("${command_name}" --version 2>&1 || true)"
      ;;
    yq)
      raw="$("${command_name}" --version 2>&1 || true)"
      ;;
    argocd)
      raw="$("${command_name}" version --client --short 2>&1 || true)"
      ;;
    kubeconform)
      raw="$("${command_name}" -v 2>&1 || true)"
      ;;
    *)
      raw="$("${command_name}" --version 2>&1 || true)"
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
  local latest_status="$3"

  if [[ "${latest_status}" != "ok" ]]; then
    printf '%s' "${latest_status}"
    return
  fi

  if [[ "${local_version}" == "missing" ]]; then
    printf '%s' "missing"
    return
  fi

  if [[ -z "${local_version}" || "${local_version}" == "unknown" ]]; then
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
  local latest_reason="$2"

  case "${status}" in
    current) printf '%s' "local matches latest" ;;
    outdated) printf '%s' "local differs from latest" ;;
    missing) printf '%s' "command not found" ;;
    version_unknown) printf '%s' "local version command failed" ;;
    api_error|asset_not_found) printf '%s' "${latest_reason}" ;;
    *) printf '%s' "unknown status" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fail-on-outdated)
      FAIL_ON_OUTDATED=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

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

trap cleanup EXIT
CURL_CONFIG=""
create_curl_config
arch="$(detect_arch)"
exit_status=0
output="| Tool | Repository | Local version | Latest tag | Status | Reason |"
output+=$'\n''|---|---|---|---|---|---|'

for tool in "${TOOL_NAMES[@]}"; do
  repo="${TOOL_REPOS[${tool}]}"
  IFS=$'\t' read -r latest_tag latest_status latest_reason < <(latest_release_info "${repo}" "${tool}" "${arch}")
  local_version="$(local_version_for_command "${tool}")"

  if [[ -z "${local_version}" ]]; then
    local_version="unknown"
  fi

  status="$(status_for_versions "${local_version}" "${latest_tag}" "${latest_status}")"
  reason="$(reason_for_status "${status}" "${latest_reason}")"

  case "${status}" in
    current) ;;
    outdated|missing|version_unknown|api_error|asset_not_found)
      exit_status=1
      ;;
    *)
      status="version_unknown"
      reason="unknown status"
      exit_status=1
      ;;
  esac

  output+=$'\n'"| ${tool} | ${repo} | ${local_version} | ${latest_tag} | ${status} | ${reason} |"
done

printf '%s\n' "${output}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '%s\n' "${output}" >> "${GITHUB_STEP_SUMMARY}"
fi

if [[ ${FAIL_ON_OUTDATED} -eq 1 && ${exit_status} -ne 0 ]]; then
  exit 1
fi

exit 0
