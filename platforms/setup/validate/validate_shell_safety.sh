#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_shell_safety.sh
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

# shell script の重大事故パターンを検知する品質ゲート。
# legacy script の pipefail 不足は warning に留め、setup.sh / lib / validate 系は blocking にする。

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
      platforms/setup/setup.sh|platforms/setup/lib/*.sh|platforms/setup/validate/*.sh)
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
done < <(find platforms/scripts platforms/setup -type f -name "*.sh" -print0)

if [[ ${FAILED} -eq 0 ]]; then
  echo "PASSED: Shell safety gate（shell 安全性検証 OK）"
else
  echo "FAILED: Shell safety gate（shell 安全性検証 NG）" >&2
fi

exit "${FAILED}"
