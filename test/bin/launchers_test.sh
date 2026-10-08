#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_tmp="$(mktemp -d)"

cleanup() {
  rm -rf "$test_tmp"
  rm -f "$repo_root/tmp/tls/launchers-test.example.ts.net.crt" \
    "$repo_root/tmp/tls/launchers-test.example.ts.net.key"
}

trap cleanup EXIT
fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

fail() { echo "FAIL: $*" >&2; exit 1; }

assert_line() {
  local file="$1" expected="$2"
  local line
  while IFS= read -r line; do
    [[ "$line" == "$expected" ]] && return 0
  done <"$file"
  fail "expected $file to contain $expected"
}

make_executable() {
  local name="$1"
  shift
  {
    echo '#!/usr/bin/env bash'
    printf '%s\n' "$@"
  } >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

for command in bash python3 dirname jq mkdir chmod mktemp mv rm readlink; do
  ln -s "$(command -v "$command")" "$fake_bin/$command"
done

make_executable mix \
  'printf "%s\n" "$PWD" "$VXPIPE_DEV_TLS" "${APP_HOST:-}" "${VXPIPE_TAILSCALE_IP:-}" "${VXPIPE_DEV_TLS_CERTFILE:-}" "${VXPIPE_TEST_DOTENV:-}" "$@" >"$VXPIPE_TEST_COMMAND_LOG"'
make_executable npm \
  'printf "%s\n" "$PWD" "$VXPIPE_DEV_TLS" "${APP_HOST:-}" "${VXPIPE_TAILSCALE_IP:-}" "${VXPIPE_DEV_TLS_CERTFILE:-}" "${ASTRO_DEV_BACKGROUND:-}" "$@" >"$VXPIPE_TEST_COMMAND_LOG"'

app_log="$test_tmp/app"
site_log="$test_tmp/site"
PATH="$fake_bin" VXPIPE_TEST_COMMAND_LOG="$app_log" "$repo_root/bin/dev"
assert_line "$app_log" "$repo_root"
assert_line "$app_log" "http"
assert_line "$app_log" "run"
assert_line "$app_log" "--no-halt"

mkdir -p "$test_tmp/repo/bin"
cp "$repo_root/bin/dev" "$repo_root/bin/worktree-port" "$test_tmp/repo/bin/"
cp -R "$repo_root/bin/lib" "$test_tmp/repo/bin/lib"
printf '%s\n' 'VXPIPE_TEST_DOTENV=loaded' >"$test_tmp/repo/.env"
PATH="$fake_bin" VXPIPE_TEST_COMMAND_LOG="$app_log" "$test_tmp/repo/bin/dev"
assert_line "$app_log" "loaded"

PATH="$fake_bin" VXPIPE_TEST_COMMAND_LOG="$site_log" "$repo_root/bin/site-dev"
assert_line "$site_log" "$repo_root"
assert_line "$site_log" "http"
assert_line "$site_log" "0"
assert_line "$site_log" "--prefix"
assert_line "$site_log" "vxpipe-docs"
assert_line "$site_log" "dev"

for launcher in dev site-dev; do
  if output="$(PATH="$fake_bin" "$repo_root/bin/$launcher" --invalid 2>&1)"; then
    fail "expected bin/$launcher to reject invalid arguments"
  fi
  [[ "$output" == *"Usage: bin/$launcher [--tailscale]"* ]] ||
    fail "expected bin/$launcher usage"
done

make_executable tailscale \
  'case "${1:-}" in' \
  '  status) printf "%s\n" '\''{"Self":{"DNSName":"launchers-test.example.ts.net.","TailscaleIPs":["100.64.0.12"]}}'\'' ;;' \
  '  cert) printf "%s\n" "certificate" ;;' \
  'esac'

PATH="$fake_bin" VXPIPE_TEST_COMMAND_LOG="$app_log" "$repo_root/bin/dev" --tailscale
assert_line "$app_log" "phoenix"
assert_line "$app_log" "launchers-test.example.ts.net"
assert_line "$app_log" "100.64.0.12"
assert_line "$app_log" "$repo_root/tmp/tls/launchers-test.example.ts.net.crt"

PATH="$fake_bin" VXPIPE_TEST_COMMAND_LOG="$site_log" "$repo_root/bin/site-dev" --tailscale
assert_line "$site_log" "phoenix"
assert_line "$site_log" "launchers-test.example.ts.net"
assert_line "$site_log" "100.64.0.12"
assert_line "$site_log" "$repo_root/tmp/tls/launchers-test.example.ts.net.crt"

echo "launcher integration tests passed"
