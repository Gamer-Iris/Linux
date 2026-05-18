#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_readme.sh
# 引数       : [README path]（省略時: README.md）
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/19                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

# README.md の退行を検知する品質ゲート。固定手順番号や旧見出し、危険な構築導線を禁止する。

README="${1:-README.md}"
FAILED=0

if [[ ! -f "${README}" ]]; then
  echo "ERROR: README が見つかりません: ${README}" >&2
  exit 1
fi

echo "=== README quality gate（README 品質検証）: ${README} ==="

######################################################################################################################################################
# check_absent 関数
# @param  $1 : 検出禁止にする grep 拡張正規表現
# @param  $2 : 検出時に表示するエラーメッセージ
# @return なし（FAILED を更新）
######################################################################################################################################################
check_absent() {
  local pattern="$1"
  local message="$2"
  if grep -nE "${pattern}" "${README}"; then
    echo "ERROR: ${message}" >&2
    FAILED=1
  fi
}

check_absent '手順[0-9０-９]+' \
  "固定手順番号参照が残っています。章名で参照してください。"
check_absent '★⑪|★⑫' \
  "古い星印プレースホルダー参照が残っています。意味のある名前へ置換してください。"
check_absent 'inventory\.py' \
  "古い inventory.py 参照が残っています。inventory.sh に統一してください。"
check_absent '【操作方法】' \
  "旧見出し【操作方法】が残っています。【運用手順】等へ分離してください。"
check_absent 'ssh-keygen -t ed25519 -f \./argo' \
  "古い Argo CD Deploy Key 作成例が残っています。~/.ssh/argo を使用してください。"
check_absent '(^|[[:space:]`"(])docs/|platforms/runbooks/' \
  "README から別 Markdown への参照が残っています。README.md に要点を統合してください。"
check_absent 'platforms/scripts/(validate_readme|validate_shell_safety|validate_python|validate_k8s_policy|check_secrets)\.(sh|py)' \
  "品質検証スクリプトの旧パスが残っています。platforms/setup/validate/ に統一してください。"
check_absent 'platforms/scripts/(minecraft_start|minecraft_stop|minecraft_backup_server|minecraft_restore_server|kubernetes_cron)\.sh' \
  "運用スクリプトの旧パスが残っています。minecraft/ または kubernetes/ 配下へ統一してください。"

extra_markdown=$(find . -type f -name "*.md" ! -path "./README.md" ! -path "./platforms/applications/*/target/*" -print)
if [[ -n "${extra_markdown}" ]]; then
  echo "${extra_markdown}"
  echo "ERROR: README.md 以外の Markdown が残っています。README.md へ統合してください。" >&2
  FAILED=1
fi

if grep -nE '^[[:space:]]*\./setup\.sh all[[:space:]]*$' "${README}" >/dev/null; then
  precheck_line=$(grep -nE '^[[:space:]]*\./setup\.sh --precheck[[:space:]]*$' "${README}" | head -n 1 | cut -d: -f1 || true)
  dryrun_line=$(grep -nE '^[[:space:]]*\./setup\.sh all --dry-run[[:space:]]*$' "${README}" | head -n 1 | cut -d: -f1 || true)
  run_line=$(grep -nE '^[[:space:]]*\./setup\.sh all[[:space:]]*$' "${README}" | head -n 1 | cut -d: -f1 || true)
  if [[ -z "${precheck_line}" || -z "${dryrun_line}" || -z "${run_line}" ||
        "${precheck_line}" -ge "${run_line}" || "${dryrun_line}" -ge "${run_line}" ]]; then
    echo "ERROR: ./setup.sh all は --precheck と --dry-run の後に記載してください。" >&2
    FAILED=1
  fi
fi

if [[ ${FAILED} -eq 0 ]]; then
  echo "PASSED: README quality gate（README 品質検証 OK）"
else
  echo "FAILED: README quality gate（README 品質検証 NG）" >&2
fi

exit "${FAILED}"
