#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_shell_safety.sh
# 引数       : なし
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# shell script の重大事故パターンを検知する品質ゲート。
# legacy script の pipefail 不足は warning に留め、setup.sh / lib / validate 系は blocking にする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

FAILED=0

echo "=== Shell safety gate（shell 安全性検証） ==="

# platforms/setup と platforms/scripts の shell script を対象にする。
# inventory.sh は Python 実装の dynamic inventory なので除外する。
while IFS= read -r -d '' file; do
  if [[ "${file}" == *"inventory.sh" ]]; then
    continue
  fi

  if ! grep -qE '^set -euo pipefail' "${file}"; then
    case "${file}" in
      */platforms/setup/setup.sh|*/platforms/setup/lib/*.sh|*/platforms/setup/validate/*.sh)
        echo "ERROR: ${file}: set -euo pipefail がありません。" >&2
        FAILED=1
        ;;
      *)
        echo "WARNING: ${file}: set -euo pipefail がありません。legacy script として許容します。"
        ;;
    esac
  fi

  if grep -nE 'rm[[:space:]]+-rf[[:space:]]+/?[[:space:]]*$' "${file}"; then
    echo "ERROR: ${file}: root 付近を削除し得る rm -rf パターンがあります。" >&2
    FAILED=1
  fi

  if grep -nE 'rm[[:space:]]+-rf[[:space:]]+(\*|\.[^[:space:]]*\*)' "${file}"; then
    echo "ERROR: ${file}: wildcard を直接削除する rm -rf パターンがあります。" >&2
    FAILED=1
  fi

  if grep -nE 'sudo[[:space:]]+rm[[:space:]]+-r(f)?[[:space:]]+(\*|\.[^[:space:]]*\*)' "${file}"; then
    echo "ERROR: ${file}: sudo rm で wildcard を削除しています。" >&2
    FAILED=1
  fi
done < <(find "${REPO_ROOT}/platforms/scripts" "${REPO_ROOT}/platforms/setup" -type f -name "*.sh" -print0)

AUTO_UPDATE_WORKFLOW="${REPO_ROOT}/.github/workflows/local-tools-auto-update.yml"

if [[ -f "${AUTO_UPDATE_WORKFLOW}" ]]; then
  if ! grep -qE '^[[:space:]]*schedule:' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: schedule trigger がありません。" >&2
    FAILED=1
  fi

  if ! grep -qE '^[[:space:]]*workflow_dispatch:' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: workflow_dispatch trigger がありません。" >&2
    FAILED=1
  fi

  if grep -qE '^[[:space:]]*(push|pull_request):' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: push / pull_request trigger は許可しません。" >&2
    FAILED=1
  fi

  if ! grep -qE '^[[:space:]]*contents:[[:space:]]*read[[:space:]]*$' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: permissions.contents は read にしてください。" >&2
    FAILED=1
  fi

  if ! grep -qE 'update-local-tools\.sh.*--apply' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: update-local-tools.sh --apply を実行していません。" >&2
    FAILED=1
  fi

  if grep -q 'settings_secret.yml' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: settings_secret.yml を参照しています。" >&2
    FAILED=1
  fi

  if grep -qE '\b(kubectl|kubeadm|kubelet|containerd)\b' "${AUTO_UPDATE_WORKFLOW}"; then
    echo "ERROR: ${AUTO_UPDATE_WORKFLOW}: Kubernetes node component を更新対象に含めないでください。" >&2
    FAILED=1
  fi
fi

if [[ ${FAILED} -eq 0 ]]; then
  echo "PASSED: Shell safety gate（shell 安全性検証 OK）"
else
  echo "FAILED: Shell safety gate（shell 安全性検証 NG）" >&2
fi

exit "${FAILED}"
