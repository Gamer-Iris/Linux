#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_readme.sh
# 引数       : [README path]（省略時: REPO_ROOT/README.md）
# 復帰値     : 0 （正常終了）
#            : 1 （異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/06/27                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

README="${1:-${REPO_ROOT}/README.md}"
FAILED=0

if [[ ! -f "${README}" ]]; then
  echo "ERROR: README が見つかりません: ${README}" >&2
  exit 1
fi

echo "=== README quality gate（README 品質検証）: ${README} ==="

######################################################################################################################################################
# check_absent 関数
######################################################################################################################################################
check_absent() {
  local pattern="$1"
  local message="$2"
  if grep -nE "${pattern}" "${README}"; then
    echo "ERROR: ${message}" >&2
    FAILED=1
  fi
}

# 「手順5」はスペースなし表記で禁止。「手順 5「...」」はスペースあり表記で許可。
check_absent '手順([0-9]|０|１|２|３|４|５|６|７|８|９)+' \
  "固定手順番号参照が残っています。章名で参照してください。"
# 「details 5」は Markdown 実装寄り表記で禁止。利用者向けには「手順 5」を使う。
check_absent 'details[[:space:]]+[0-9]' \
  "details は実装用語です。利用者向けには「手順 N「章名」」を使用してください。"
if grep -nF -e '★⑪' -e '★⑫' "${README}"; then
  echo "ERROR: 古い星印プレースホルダー参照が残っています。意味のある名前へ置換してください。" >&2
  FAILED=1
fi
check_absent 'inventory\.py' \
  "古い inventory.py 参照が残っています。inventory.sh に統一してください。"
check_absent '【操作方法】' \
  "旧見出し【操作方法】が残っています。【運用手順】等へ分離してください。"
check_absent 'ssh-keygen -t ed25519 -f \./argo' \
  "古い Argo CD Deploy Key 作成例が残っています。~/.ssh/argo を使用してください。"
if grep -nE '(^|[[:space:]`"(])docs/' "${README}"; then
  echo "ERROR: README から docs/ への参照が残っています。README.md に要点を統合してください。" >&2
  FAILED=1
fi
check_absent 'platforms/runbooks/' \
  "README から runbook Markdown への参照が残っています。README.md に要点を統合してください。"
check_absent 'platforms/scripts/(validate_readme|validate_shell_safety|validate_python|validate_k8s_policy|check_secrets)\.(sh|py)' \
  "品質検証スクリプトの旧パスが残っています。platforms/setup/validate/ に統一してください。"
check_absent 'platforms/scripts/(minecraft_start|minecraft_stop|minecraft_backup_server|minecraft_restore_server|kubernetes_cron)\.sh' \
  "運用スクリプトの旧パスが残っています。minecraft/ または kubernetes/ 配下へ統一してください。"

extra_markdown=$(find "${REPO_ROOT}" -type f -name "*.md" \
  ! -path "${REPO_ROOT}/README.md" \
  ! -path "${REPO_ROOT}/platforms/applications/*/target/*" \
  -print)
if [[ -n "${extra_markdown}" ]]; then
  echo "${extra_markdown}"
  echo "ERROR: 許可外 Markdown が残っています。README.md へ統合するか validate_readme.sh の許可リストを更新してください。" >&2
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

######################################################################################################################################################
# Markdown 構造チェック（改行崩れ・可読性劣化の再発防止）
######################################################################################################################################################
line_count=$(wc -l < "${README}")
if [[ "${line_count}" -lt 100 ]]; then
  echo "ERROR: README.md の行数が少なすぎます（${line_count} 行）。Markdown 改行が崩れている可能性があります。" >&2
  FAILED=1
fi
if [[ "${line_count}" -gt 1000 ]]; then
  echo "WARNING: README.md が ${line_count} 行あります。冗長な記載がないか確認してください。" >&2
fi

fence_count=$(grep -c '^```' "${README}" || true)
if (( fence_count % 2 != 0 )); then
  echo "ERROR: README.md の fenced code block 数が奇数です（${fence_count} 個）。閉じ忘れがあります。" >&2
  FAILED=1
fi

if grep -nE '^#{1,6} .*(\*\*|```|\|---\|)' "${README}"; then
  echo "ERROR: 見出し行に本文・表・コードブロックが連結されています。改行が崩れています。" >&2
  FAILED=1
fi

table_sep_count=$(grep -c '|---|' "${README}" || true)
if [[ "${table_sep_count}" -eq 0 ]]; then
  echo "ERROR: README.md に表区切り（|---|）が見つかりません。表が崩れている可能性があります。" >&2
  FAILED=1
fi

h2_count=$(grep -c '^## ' "${README}" || true)
if [[ "${h2_count}" -eq 0 ]]; then
  echo "ERROR: README.md に ## 見出しが見つかりません。" >&2
  FAILED=1
fi

if grep -nPzo '\n\n\n\n' "${README}" >/dev/null 2>&1; then
  echo "ERROR: README.md に3行以上の連続空行があります。" >&2
  FAILED=1
fi

details_count=$(grep -c '<details>' "${README}" || true)
if [[ "${line_count}" -gt 350 && "${details_count}" -lt 3 ]]; then
  echo "WARNING: README.md が ${line_count} 行ありますが <details> が ${details_count} 個しかありません。" >&2
fi

######################################################################################################################################################
# details ブロック単位チェック
######################################################################################################################################################
if [[ "${details_count}" -gt 0 ]]; then
  current_summary=""
  in_details=false
  has_purpose=false
  has_todo=false
  has_done=false
  while IFS= read -r line; do
    if [[ "${line}" == *"<details>"* ]]; then
      in_details=true
      has_purpose=false
      has_todo=false
      has_done=false
      current_summary=""
    fi
    if [[ "${line}" == *"<summary>"* ]]; then
      current_summary=$(echo "${line}" | sed 's/.*<summary>//;s/<\/summary>.*//')
    fi
    if ${in_details}; then
      [[ "${line}" == *"この章の目的:"* ]] && has_purpose=true
      [[ "${line}" == *"この章でやること:"* ]] && has_todo=true
      [[ "${line}" == *"完了条件:"* ]] && has_done=true
    fi
    if [[ "${line}" == *"</details>"* ]] && ${in_details}; then
      ${has_purpose} || echo "WARNING: [${current_summary}] に「この章の目的:」がありません。" >&2
      ${has_todo}    || echo "WARNING: [${current_summary}] に「この章でやること:」がありません。" >&2
      ${has_done}    || echo "WARNING: [${current_summary}] に「完了条件:」がありません。" >&2
      in_details=false
    fi
  done < "${README}"
fi

######################################################################################################################################################
# 句点改行チェック
# NG1: 同一行で句点後に文章が続く（。<br> は許可）
# NG2: 句点で終わる行の次の非空行が通常文（soft break = GitHub 表示で連結される）
#      。<br> で終わる行、次が空行、次が箇条書き・見出し・表・HTML タグ行は許可
######################################################################################################################################################
readarray -t readme_lines < "${README}"
total_lines=${#readme_lines[@]}
in_code=false
is_excluded() {
  local s="${1#"${1%%[![:space:]]*}"}"
  [[ -z "${s}" ]] && return 0
  [[ "${s}" == '|'* ]] && return 0
  [[ "${s}" == '#'* ]] && return 0
  [[ "${s}" == '```'* ]] && return 0
  [[ "${s}" == '<details'* || "${s}" == '</details'* || "${s}" == '<summary'* ]] && return 0
  [[ "${s}" == *'http://'* || "${s}" == *'https://'* ]] && return 0
  [[ "${s}" == '- '* || "${s}" == '1.'* || "${s}" == '2.'* || "${s}" == '3.'* || "${s}" == '4.'* ]] && return 0
  return 1
}
for (( i=0; i<total_lines; i++ )); do
  line="${readme_lines[$i]}"
  stripped="${line#"${line%%[![:space:]]*}"}"
  if [[ "${stripped}" == '```'* ]]; then
    if ${in_code}; then in_code=false; else in_code=true; fi
    continue
  fi
  ${in_code} && continue
  is_excluded "${line}" && continue || true
  if [[ "${stripped}" == *'。'* ]] && [[ "${stripped}" != *'。' ]] && [[ "${stripped}" != *'。<br>' ]]; then
    echo "ERROR: 句点の後に文章が続いています: ${line}" >&2
    FAILED=1
  fi
  period_count=$(echo "${stripped}" | grep -o '。' | wc -l || true)
  if [[ "${period_count}" -ge 2 ]] && [[ "${stripped}" != *'。<br>'* ]]; then
    echo "ERROR: 1行に句点が2個以上あります: ${line}" >&2
    FAILED=1
  fi
  if [[ "${stripped}" == *'。' ]] && [[ "${stripped}" != *'。<br>' ]]; then
    j=$((i + 1))
    if [[ ${j} -lt ${total_lines} ]]; then
      next_stripped="${readme_lines[$j]#"${readme_lines[$j]%%[![:space:]]*}"}"
      next_excluded=false
      is_excluded "${readme_lines[$j]}" && next_excluded=true || true
      if [[ -n "${next_stripped}" ]] && ! ${next_excluded}; then
        echo "ERROR: 句点で終わる行の次行が通常文です（soft break）: ${line}" >&2
        FAILED=1
      fi
    fi
  fi
done

if [[ ${FAILED} -eq 0 ]]; then
  echo "PASSED: README quality gate（README 品質検証 OK）"
else
  echo "FAILED: README quality gate（README 品質検証 NG）" >&2
fi

exit "${FAILED}"
