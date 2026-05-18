#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_python.sh
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

# Python 実装資材の構文チェックを行う。Git Bash の python3 shim 対策として python へフォールバックする。

echo "=== Python syntax check（Python 構文検証） ==="
PYTHON_BIN="${PYTHON_BIN:-}"

if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: python3 または python が見つからないか実行できません。" >&2
    exit 1
  fi
fi

"${PYTHON_BIN}" -m py_compile platforms/setup/inventory.sh
"${PYTHON_BIN}" -m py_compile platforms/setup/validate/validate_k8s_policy.py
echo "PASSED: Python syntax check（Python 構文検証 OK）"
