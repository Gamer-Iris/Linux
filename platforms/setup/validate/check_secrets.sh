#!/bin/bash

######################################################################################################################################################
# ファイル   : check_secrets.sh
# 引数       : [secrets_dir]（省略時は platforms/kubernetes/apps/secrets）
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

SECRETS_DIR="${1:-${REPO_ROOT}/platforms/kubernetes/apps/secrets}"
SETTINGS_TEMPLATE="${REPO_ROOT}/platforms/settings/settings_secret_template.yml"
SETTINGS_FILE="${REPO_ROOT}/platforms/settings/settings_secret.yml"
FAILED=0
CHECKED=0

# ── settings_secret.yml の SMB 設定確認 ───────────────────────────────────
if [[ ! -f "${SETTINGS_TEMPLATE}" ]]; then
  echo "  ERROR: settings_secret_template.yml が見つかりません: ${SETTINGS_TEMPLATE}" >&2
  FAILED=1
elif ! awk '
  /^smb:/ { in_smb=1; next }
  in_smb && /^[^[:space:]]/ { in_smb=0 }
  in_smb && /^[[:space:]]+ip:/ { ip=1 }
  in_smb && /^[[:space:]]+username:/ { username=1 }
  in_smb && /^[[:space:]]+password:/ { password=1 }
  END { exit (ip && username && password) ? 0 : 1 }
' "${SETTINGS_TEMPLATE}"; then
  echo "  ERROR: settings_secret_template.yml に smb.ip / smb.username / smb.password がありません。" >&2
  FAILED=1
fi

if [[ -f "${SETTINGS_FILE}" ]] && ! awk '
  /^smb:/ { in_smb=1; next }
  in_smb && /^[^[:space:]]/ { in_smb=0 }
  in_smb && /^[[:space:]]+ip:/ { ip=1 }
  in_smb && /^[[:space:]]+username:/ { username=1 }
  in_smb && /^[[:space:]]+password:/ { password=1 }
  END { exit (ip && username && password) ? 0 : 1 }
' "${SETTINGS_FILE}"; then
  echo "  ERROR: settings_secret.yml に smb.ip / smb.username / smb.password がありません。" >&2
  FAILED=1
fi

# ── secrets_dir の存在確認 ─────────────────────────────────────────────────
if [[ ! -d "${SECRETS_DIR}" ]]; then
  echo "WARNING: secrets ディレクトリが見つかりません: ${SECRETS_DIR}"
  echo "         setup.sh secrets 実行前は未作成で正常です。"
  exit "${FAILED}"
fi

echo "=== K8s Secret / SealedSecret check: ${SECRETS_DIR} ==="
echo ""

# ── 各 Secret / SealedSecret ファイルを検査 ───────────────────────────────
while IFS= read -r -d '' file; do
  # SealedSecret は暗号化済みのため Git 管理可
  if grep -q "kind: SealedSecret" "${file}" 2>/dev/null; then
    CHECKED=$((CHECKED + 1))
    echo "  OK: ${file} (SealedSecret)"
    continue
  fi

  # K8s Secret マニフェストは replace-me のみ許可
  if ! grep -q "kind: Secret" "${file}" 2>/dev/null; then
    continue
  fi

  CHECKED=$((CHECKED + 1))

  # stringData: セクションが存在するか
  if grep -q "^stringData:" "${file}"; then
    if grep -q "replace-me" "${file}"; then
      echo "  OK: ${file}"
    else
      echo "  SECURITY ERROR: ${file}"
      echo "    stringData: セクションに 'replace-me' が見つかりません。"
      echo "    実際の認証情報が含まれている可能性があります。"
      echo "    Git に push する前に確認してください。"
      FAILED=1
    fi
  fi

  # data: セクション（base64）が存在する場合は警告
  if grep -q "^data:" "${file}"; then
    echo "  WARNING: ${file}"
    echo "    'data:' (base64) セクションが存在します。"
    echo "    base64 値が実際の認証情報でないことを手動で確認してください。"
    echo "    推奨: 'stringData: replace-me' 形式に統一してください。"
  fi

done < <(find "${SECRETS_DIR}" -maxdepth 1 \( -name "*.yml" -o -name "*.yaml" \) -print0 2>/dev/null)

echo ""

# ── 結果サマリ ──────────────────────────────────────────────────────────────
if [[ ${CHECKED} -eq 0 ]]; then
  echo "WARNING: ${SECRETS_DIR} に K8s Secret / SealedSecret ファイルが見つかりませんでした。"
fi

if [[ ${FAILED} -eq 0 ]]; then
  echo "PASSED: ${CHECKED} 件の Secret / SealedSecret ファイルを確認しました。"
else
  echo "FAILED: 潜在的な認証情報漏洩が検知されました。コミット前に確認してください。"
  echo ""
  echo "対処法:"
  echo "  1. 該当ファイルの実値を 'replace-me' に戻してから git commit する"
  echo "  2. settings_secret.yml から kubeseal で SealedSecret を生成してから commit する"
fi

exit "${FAILED}"
