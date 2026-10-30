#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/publish-verified-release.sh"
bash -n "$script"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"

cat > "$temp/bin/gh" <<'GH_MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'api repos/'*) printf '%s\n' "$TEST_SHA" ;;
  'run view') printf '{"headSha":"%s","status":"completed","conclusion":"success"}\n' "$TEST_SHA" ;;
  'release view')
    if [[ "$3" == "${TEST_EXISTING_TAG:-}" && -n "${TEST_EXISTING_TAG:-}" ]]; then
      if [[ " $* " == *' --json body '* ]]; then printf '%s\n' "${TEST_EXISTING_BODY:-}"; fi
      exit 0
    fi
    exit 1 ;;
  'release list')
    if [[ -n "${TEST_EXISTING_TAG:-}" ]]; then
      printf '[{"tagName":"%s"}]\n' "$TEST_EXISTING_TAG"
    else
      echo '[]'
    fi ;;
  'run download') echo 'ARTIFACT_DOWNLOAD_ATTEMPTED'; exit 95 ;;
  *) echo "Unexpected gh call: $*" >&2; exit 98 ;;
esac
GH_MOCK
cat > "$temp/bin/git" <<'GIT_MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  fetch|merge-base) exit 0 ;;
  rev-parse) printf '%s\n' "$TEST_SHA" ;;
  show)
    case "$2" in
      *:sapi/PHP-VERSION.conf) echo 8.4.27 ;;
      *:sapi/SWOOLE-VERSION.conf) echo v6.2.4 ;;
      *:sapi/src/builder/extension/protobuf.php)
        printf "            ->withPeclVersion('%s')\n" "${TEST_PROTOBUF_VERSION:-5.36.2}" ;;
      *:sapi/src/builder/extension/xlswriter.php)
        echo "            ->withPeclVersion('3.0.0')" ;;
      *) echo "Unexpected git show $2" >&2; exit 97 ;;
    esac ;;
  *) echo "Unexpected git call: $*" >&2; exit 98 ;;
esac
GIT_MOCK
chmod +x "$temp/bin/gh" "$temp/bin/git"
export PATH="$temp/bin:$PATH"
export GITHUB_REPOSITORY='hjw0968/swoole-cli'
export TEST_SHA='1111111111111111111111111111111111111111'
export LINUX_RUN_ID=1 MACOS_RUN_ID=2
export TEST_EXISTING_TAG='v6.2.4-php8.4.27-g9ae5527'
export TEST_EXISTING_BODY=$'| PHP | 8.4.27 (ZTS) |\n| Swoole | 6.2.4 |\n| protobuf | 5.36.2 |\n| xlswriter | 3.0.0 |'

expect_case() {
  local label="$1" expected_exit="$2" expected_text="$3" out rc
  set +e
  out="$(bash "$script" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" || "$out" != *"$expected_text"* ]]; then
    printf '[FAIL] %s: exit=%s output=%s\n' "$label" "$rc" "$out" >&2
    exit 1
  fi
  printf '[PASS] %s\n' "$label"
}

expect_case 'Legacy SHA release prevents duplicate' 0 'already covers PHP 8.4.27'
TEST_PROTOBUF_VERSION=5.36.3 expect_case 'PECL-only upgrade allows new release' 95 'ARTIFACT_DOWNLOAD_ATTEMPTED'
TEST_EXISTING_TAG= expect_case 'No previous release allows publication' 95 'ARTIFACT_DOWNLOAD_ATTEMPTED'
TEST_EXISTING_BODY='No PECL metadata' expect_case 'Unknown legacy metadata fails closed' 1 'lacks PECL version metadata'
RELEASE_TAG=v6.2.4-php8.4.27-r2 expect_case 'Explicit revision allows intentional rebuild' 95 'ARTIFACT_DOWNLOAD_ATTEMPTED'
RELEASE_TAG=v6.2.3-php8.4.27-r2 expect_case 'Manual revision must match source version' 1 'Manual tag must match'
TEST_EXISTING_TAG=v6.2.4-php8.4.27-pb5.36.2-xls3.0.0 expect_case 'Exact automatic tag prevents duplicate' 0 'already exists'
echo 'Release dedup policy: 7 passed'
