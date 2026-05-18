#!/bin/bash

######################################################################################################################################################
# ファイル   : validate_release_workflows.sh
# 引数       : なし
# 復帰値     : 0（正常終了）
#            : 1（異常終了）
#
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# 【修正履歴】
# V-001      : 2026/05/18                 Gamer-Iris   新規作成
#
######################################################################################################################################################

set -euo pipefail

FAILED=0
FAIL_COUNT=0
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"

# shellcheck disable=SC2329
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "=== Release workflow validation（Release workflow 検証） ==="

fail() {
  echo "ERROR: $1" >&2
  FAILED=1
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_case_debug() {
  local label="$1"
  local output="$2"
  local case_path="$3"
  local gh_lookup="$4"

  echo "--- ${label} debug begin ---" >&2
  echo "PATH=${case_path}" >&2
  if [[ -n "${gh_lookup}" ]]; then
    echo "command -v gh: ${gh_lookup}" >&2
  else
    echo "command -v gh: (not found)" >&2
  fi
  echo "--- ${label} debug end ---" >&2

  echo "--- ${label} output begin ---" >&2
  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" >&2
  else
    echo "(empty)" >&2
  fi
  echo "--- ${label} output end ---" >&2
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${label}: '${needle}' が含まれていません"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "${label}: '${needle}' は含めないでください"
  fi
}

assert_gh_requirement_message() {
  local haystack="$1"
  local label="$2"

  if [[ ! "${haystack}" =~ [Gg]it[Hh]ub[[:space:]]+CLI ]]; then
    fail "${label}: 出力に GitHub CLI の説明がありません"
  fi

  if [[ "${haystack}" != *"gh"* ]]; then
    fail "${label}: 出力に gh コマンドの説明がありません"
  fi

  if [[ ! "${haystack}" =~ ([Rr]equired|必要) ]]; then
    fail "${label}: gh が必要であることが出力から分かりません"
  fi
}

assert_publish_case_message() {
  local case_name="$1"
  local haystack="$2"

  case "${case_name}" in
    no-publish)
      assert_contains "${haystack}" "--no-publish" "${case_name}"
      assert_contains "${haystack}" "dispatch" "${case_name}"
      ;;
    missing-gh)
      assert_gh_requirement_message "${haystack}" "${case_name}"
      ;;
    auth-fail)
      if [[ ! "${haystack}" =~ [Gg]it[Hh]ub[[:space:]]+CLI ]]; then
        fail "${case_name}: 出力に GitHub CLI の説明がありません"
      fi
      assert_contains "${haystack}" "github.com" "${case_name}"
      if [[ ! "${haystack}" =~ (認証|auth) ]]; then
        fail "${case_name}: GitHub 認証に失敗したことが出力から分かりません"
      fi
      ;;
    view-fail)
      assert_contains "${haystack}" "build-release.yml" "${case_name}"
      ;;
    run-fail)
      assert_contains "${haystack}" "workflow" "${case_name}"
      assert_contains "${haystack}" "dispatch" "${case_name}"
      ;;
    dry-run)
      assert_contains "${haystack}" "dry-run" "${case_name}"
      assert_contains "${haystack}" "dispatch" "${case_name}"
      ;;
    default-publish)
      assert_contains "${haystack}" "deploy_to_servers=false" "${case_name}"
      ;;
    *)
      fail "${case_name}: 未対応の publish case message check です"
      ;;
  esac
}

write_tool_stubs() {
  local bin_dir="$1"
  mkdir -p "${bin_dir}"

  cat > "${bin_dir}/date" <<'EOF'
#!/bin/sh
echo "2026/05/18 00:00:00"
EOF
  chmod +x "${bin_dir}/date"

  cat > "${bin_dir}/dirname" <<'EOF'
#!/bin/sh
path="${1%/}"
case "${path}" in
  */*) printf '%s\n' "${path%/*}" ;;
  *) printf '%s\n' "." ;;
esac
EOF
  chmod +x "${bin_dir}/dirname"

  cat > "${bin_dir}/tee" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in
    -a) shift 2 ;;
    *) shift ;;
  esac
done
while IFS= read -r line; do
  printf '%s\n' "$line"
done
EOF
  chmod +x "${bin_dir}/tee"
}

write_gh_stub() {
  local bin_dir="$1"
  local mode="$2"
  local calls_file="$3"

  cat > "${bin_dir}/gh" <<EOF
#!/bin/sh
MODE="${mode}"
CALLS_FILE="${calls_file}"
printf '%s\n' "\$*" >> "\${CALLS_FILE}"

case "\${MODE}:\$1 \$2" in
  auth-fail:"auth status")
    echo "GitHub 認証に失敗しました" >&2
    exit 1
    ;;
  view-fail:"workflow view")
    echo "workflow view に失敗しました" >&2
    exit 1
    ;;
  run-fail:"workflow run")
    echo "workflow run に失敗しました" >&2
    exit 1
    ;;
esac

echo "gh stub ok"
exit 0
EOF
  chmod +x "${bin_dir}/gh"
}

run_publish_case() {
  local case_name="$1"
  local gh_mode="$2"
  local dry_run="$3"
  local publish_release="$4"
  local expected_rc="$5"
  local check_output="$6"
  local bin_dir="${TMP_DIR}/${case_name}/bin"
  local calls_file="${TMP_DIR}/${case_name}/gh.calls"
  local log_file="${TMP_DIR}/${case_name}/setup.log"
  local case_path="${bin_dir}"
  local gh_lookup=""
  local output=""
  local rc=0
  local failures_before=0

  echo "CHECK: ${case_name}"

  mkdir -p "${TMP_DIR}/${case_name}"
  write_tool_stubs "${bin_dir}"
  : > "${calls_file}"

  if [[ "${gh_mode}" != "missing" ]]; then
    write_gh_stub "${bin_dir}" "${gh_mode}" "${calls_file}"
  fi

  gh_lookup="$(PATH="${case_path}" command -v gh 2>/dev/null || true)"

  set +e
  output="$(
    {
      PATH="${case_path}"
      USER="${USER:-release-test}"
      cd "${REPO_ROOT}" || exit 1
      # shellcheck source=platforms/setup/setup.sh
      source platforms/setup/setup.sh
      LOG_FILE="${log_file}"
      MODE="all"
      DRY_RUN="${dry_run}"
      PUBLISH_RELEASE="${publish_release}"
      publish_greetmate_release
    } 2>&1
  )"
  rc=$?
  set -e

  failures_before="${FAIL_COUNT}"

  if [[ "${rc}" -ne "${expected_rc}" ]]; then
    fail "${case_name}: rc=${expected_rc} を期待しましたが rc=${rc} でした。output=${output}"
  fi

  if [[ "${check_output}" == "1" ]]; then
    assert_publish_case_message "${case_name}" "${output}"
  fi

  case "${case_name}" in
    dry-run|no-publish)
      if [[ -s "${calls_file}" ]]; then
        fail "${case_name}: gh を呼び出してはいけないケースで呼び出されました"
      fi
      ;;
    default-publish)
      local calls
      calls="$(<"${calls_file}")"
      assert_contains "${calls}" "workflow view build-release.yml --repo Gamer-Iris/Linux" "${case_name}"
      assert_contains "${calls}" "workflow run build-release.yml --repo Gamer-Iris/Linux --ref main -f deploy_to_servers=false" "${case_name}"
      assert_not_contains "${calls}" "deploy_to_servers=true" "${case_name}"
      ;;
  esac

  if [[ "${FAIL_COUNT}" -gt "${failures_before}" ]]; then
    print_case_debug "${case_name}" "${output}" "${case_path}" "${gh_lookup}"
  fi
}

validate_static_workflows() {
  local python_bin="python3"

  if ! python3 --version >/dev/null 2>&1; then
    python_bin="python"
  fi

  "${python_bin}" - <<'PY'
from pathlib import Path
import re
import sys

failed = False

def fail(message: str) -> None:
    global failed
    print(f"ERROR: {message}", file=sys.stderr)
    failed = True

maintenance = Path(".github/workflows/minecraft-maintenance.yml").read_text(encoding="utf-8")
build_release = Path(".github/workflows/build-release.yml").read_text(encoding="utf-8")
setup_sh = Path("platforms/setup/setup.sh").read_text(encoding="utf-8")
readme = Path("README.md").read_text(encoding="utf-8")
readme_plain = re.sub(r"[`'\"“”‘’]", "", readme)
readme_plain = re.sub(r"\s+", " ", readme_plain)

if "PUBLISH_RELEASE=1" not in setup_sh:
    fail("setup.sh は PUBLISH_RELEASE=1 を既定値にしてください")

if "--publish|--release" not in setup_sh:
    fail("setup.sh は明示的な --publish / --release option を解釈できる必要があります")

if "--no-publish" not in setup_sh or "PUBLISH_RELEASE=0" not in setup_sh:
    fail("setup.sh は Release dispatch を無効化する --no-publish をサポートする必要があります")

if "ubuntu:rolling" in maintenance:
    fail("minecraft-maintenance.yml では ubuntu:rolling を使わないでください")

if not re.search(r"(?ms)create_pvc_maintenance_pod\(\).*?image:\s*ubuntu:latest", maintenance):
    fail("pvc-emergency-start の maintenance Pod image は ubuntu:latest にしてください")

if not re.search(r"(?ms)create_pvc_maintenance_pod\(\).*?imagePullPolicy:\s*Always", maintenance):
    fail("pvc-emergency-start の maintenance Pod imagePullPolicy は Always にしてください")

if not re.search(r"(?ms)on:\s*\n\s*workflow_dispatch:\s*\n\s*inputs:\s*\n(?:.*?\n)*?\s*deploy_to_servers:", build_release):
    fail("build-release.yml は workflow_dispatch input deploy_to_servers を定義する必要があります")

if not re.search(r"(?ms)deploy_to_servers:\s*\n(?:.*?\n)*?\s*default:\s*[\"']?false[\"']?", build_release):
    fail("deploy_to_servers の default は false にしてください")

if not re.search(r"(?ms)deploy-jar:\s*\n(?:.*?\n)*?\s*if:\s*\$\{\{\s*github\.event\.inputs\.deploy_to_servers\s*==\s*'true'\s*\}\}", build_release):
    fail("deploy-jar job は deploy_to_servers == 'true' の場合だけ実行してください")

if not re.search(r"(?ms)deploy-jar:\s*\n(?:.*?\n)*?\s*environment:\s*(?:production\s*$|\n\s*name:\s*(?:production|\$\{\{[^}]*production[^}]*\}\})\s*$)", build_release):
    fail("deploy-jar job は production Environment を使う必要があります")

if not re.search(r"(?ms)rcon-reload:\s*\n(?:.*?\n)*?\s*if:\s*\$\{\{\s*github\.event\.inputs\.deploy_to_servers\s*==\s*'true'\s*\}\}", build_release):
    fail("rcon-reload job は deploy_to_servers == 'true' の場合だけ実行してください")

if not re.search(r"(?ms)^permissions:\s*\n\s*contents:\s*write\s*$", build_release):
    fail("build-release.yml は permissions: contents: write を明示してください")

if "Check release tag does not already exist" not in build_release:
    fail("build-release.yml には release/tag 衝突の事前確認 step が必要です")

if "gh release view" not in build_release:
    fail("build-release.yml は GitHub Release の既存確認を行う必要があります")

if "git ls-remote --tags" not in build_release:
    fail("build-release.yml は origin 上の Git tag 既存確認を行う必要があります")

for forbidden in ("gh release delete", "git push --delete", "git tag -d"):
    if forbidden in build_release:
        fail(f"build-release.yml で既存 release/tag を削除・上書きしないでください: {forbidden}")

if not re.search(r"(?i)bump .*pom\.xml version|pom\.xml.*version bump|version bump.*pom\.xml|pom\.xml version .*before publishing", build_release):
    fail("build-release.yml の衝突エラーでは pom.xml version bump が必要なことを説明してください")

def require_readme_patterns(message: str, patterns: tuple[str, ...]) -> None:
    missing = [pattern for pattern in patterns if not re.search(pattern, readme_plain, re.IGNORECASE)]
    if missing:
        fail(f"{message}; 不足 pattern: {', '.join(missing)}")

require_readme_patterns(
    "README.md は deploy_to_servers=true の production 承認を説明してください",
    (
        r"deploy_to_servers\s*=\s*true",
        r"environment\s+production|production\s+environment",
        r"required\s+reviewers",
        r"prevent\s+self-?review",
    ),
)

require_readme_patterns(
    "README.md は setup.sh all が非 deploy の Release workflow を dispatch することを説明してください",
    (
        r"setup\.sh\s+all",
        r"deploy_to_servers\s*=\s*false",
        r"deploy",
        r"\u884c\u308f\u306a\u3044|\u3057\u306a\u3044|skip|\u30b9\u30ad\u30c3\u30d7",
    ),
)

require_readme_patterns(
    "README.md は setup.sh all の publish path が production 承認不要であることを説明してください",
    (
        r"setup\.sh\s+all",
        r"production\s+environment|environment\s+production",
        r"\u627f\u8a8d\u4e0d\u8981|approval\s+(is\s+)?not\s+required|does\s+not\s+require\s+.*approval",
    ),
)

require_readme_patterns(
    "README.md は publish opt-out と dry-run の挙動を説明してください",
    (
        r"setup\.sh\s+all\s+--no-publish",
        r"setup\.sh\s+all\s+--dry-run",
        r"release\s+workflow",
        r"\u8d77\u52d5\u3057\u306a\u3044|dispatch\s+.*(skip|not)|\u30b9\u30ad\u30c3\u30d7",
    ),
)

if not re.search(r"github\s+cli", readme_plain, re.IGNORECASE):
    fail("README.md は Release publish に必要な GitHub CLI を説明してください")

if not re.search(r"\bgh\b", readme_plain):
    fail("README.md は Release publish に必要な gh を説明してください")

require_readme_patterns(
    "README.md は publish ありの setup.sh all で gh が必要なことを説明してください",
    (
        r"setup\.sh\s+all",
        r"publish",
        r"\bgh\b",
        r"\u5fc5\u8981|\u5931\u6557|required|must",
    ),
)

require_readme_patterns(
    "README.md は release 衝突時の挙動と version bump が必要なことを説明してください",
    (
        r"\u65e2\u5b58|already\s+exists?",
        r"release",
        r"tag",
        r"asset",
        r"\u524a\u9664.*\u4e0a\u66f8\u304d|\u4e0a\u66f8\u304d.*\u524a\u9664|delete.*overwrite|overwrite.*delete",
        r"version\s+bump|pom\.xml.*version|version.*\u4e0a\u3052",
    ),
)

sys.exit(1 if failed else 0)
PY
}

run_publish_case "no-publish" "success" "0" "0" "0" "1"
run_publish_case "missing-gh" "missing" "0" "1" "1" "1"
run_publish_case "auth-fail" "auth-fail" "0" "1" "1" "1"
run_publish_case "view-fail" "view-fail" "0" "1" "1" "1"
run_publish_case "run-fail" "run-fail" "0" "1" "1" "1"
run_publish_case "dry-run" "run-fail" "1" "1" "0" "1"
run_publish_case "default-publish" "success" "0" "1" "0" "1"

if ! validate_static_workflows; then
  FAILED=1
fi

if [[ ${FAILED} -eq 0 ]]; then
  echo "PASSED: Release workflow validation（Release workflow 検証 OK）"
else
  echo "FAILED: Release workflow validation（Release workflow 検証 NG）" >&2
fi

exit "${FAILED}"
