#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_workflow_structure.sh
# 引数       : なし
# 復帰値     : 0（正常終了）
#            : 1（異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

FAILED=0
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKFLOWS_DIR="${REPO_ROOT}/.github/workflows"

echo "=== GitHub Actions workflow structure validation（workflow 構造検証） ==="

fail() {
  echo "ERROR: $1" >&2
  FAILED=1
}

if [ ! -d "${WORKFLOWS_DIR}" ]; then
  fail ".github/workflows ディレクトリが存在しません"
  exit 1
fi

workflow_count=0

for yml in "${WORKFLOWS_DIR}"/*.yml; do
  [ -f "${yml}" ] || continue
  workflow_count=$((workflow_count + 1))
  basename_file="$(basename "${yml}")"
  line_count="$(wc -l < "${yml}")"

  if [ "${line_count}" -lt 5 ]; then
    fail "${basename_file}: ${line_count} 行しかありません（最低 5 行必要）"
    continue
  fi

  if ! grep -q '^name:' "${yml}"; then
    fail "${basename_file}: top-level 'name:' がありません"
  fi

  if ! grep -q '^on:' "${yml}" && ! grep -q "^'on':" "${yml}" && ! grep -q '^"on":' "${yml}"; then
    fail "${basename_file}: top-level 'on:' がありません"
  fi

  if ! grep -q '^jobs:' "${yml}"; then
    fail "${basename_file}: top-level 'jobs:' がありません"
  fi

  if head -1 "${yml}" | grep -q '^name:.*on:.*jobs:'; then
    fail "${basename_file}: workflow が 1 行に潰れています"
  fi
done

if [ "${workflow_count}" -eq 0 ]; then
  fail ".github/workflows に .yml ファイルがありません"
fi

for f in "${WORKFLOWS_DIR}"/*; do
  [ -f "${f}" ] || continue
  case "${f}" in
    *.yml) ;;
    *)
      basename_f="$(basename "${f}")"
      fail "${WORKFLOWS_DIR} に非 .yml ファイルがあります: ${basename_f}"
      ;;
  esac
done

if grep -rni "BuildFailed" "${WORKFLOWS_DIR}" 2>/dev/null; then
  fail "workflow 内に 'BuildFailed' への参照があります"
fi

echo ""
echo "--- actionlint 推奨 ---"
echo "actionlint が利用可能な場合、以下を実行して追加検証してください:"
echo "  actionlint ${WORKFLOWS_DIR}/*.yml"
echo ""

if [ ${FAILED} -eq 0 ]; then
  echo "PASSED: workflow structure validation（workflow 構造検証 OK: ${workflow_count} files）"
else
  echo "FAILED: workflow structure validation（workflow 構造検証 NG）" >&2
fi

exit "${FAILED}"
