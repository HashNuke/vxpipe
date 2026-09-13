#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_tmp="$(mktemp -d)"
fake_bin="$test_tmp/bin"

cleanup() {
  rm -rf "$test_tmp"
}

trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
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

assert_output_contains() {
  local output="$1"
  local expected="$2"

  [[ "$output" == *"$expected"* ]] ||
    fail "expected output to contain: $expected"
}

assert_file_has_line() {
  local path="$1"
  local expected="$2"
  local line

  while IFS= read -r line; do
    [[ "$line" == "$expected" ]] && return 0
  done <"$path"

  fail "expected $path to contain line: $expected"
}

assert_file_lacks_line() {
  local file_name="$1"
  local unexpected="$2"
  local file_line

  while IFS= read -r file_line; do
    [[ "$file_line" == "$unexpected" ]] &&
      fail "expected $file_name not to contain line: $unexpected"
  done <"$file_name"

  return 0
}

mkdir -p "$fake_bin"
ln -s "$(command -v bash)" "$fake_bin/bash"
ln -s "$(command -v dirname)" "$fake_bin/dirname"
make_executable goreman 'exit 0'

if output="$(PATH="$fake_bin" "$repo_root/bin/dev" 2>&1)"; then
  fail "expected bin/dev to reject a missing watchman executable"
fi

assert_output_contains "$output" "Error: bin/dev requires watchman on PATH."

make_executable watchman 'exit 0'

if output="$(PATH="$fake_bin" "$repo_root/bin/dev" 2>&1)"; then
  fail "expected bin/dev to reject a missing watchman-make executable"
fi

assert_output_contains "$output" "Error: bin/dev requires watchman-make on PATH."

make_executable watchman-make 'exit 0'
make_executable goreman \
  'printf "%s\n" "$@" >"$VXPIPE_TEST_GOREMAN_ARGS"' \
  'printf "%s\n" "$VXPIPE_DEV_TLS" >"$VXPIPE_TEST_DEV_TLS"'

goreman_args="$test_tmp/goreman-args"
dev_tls="$test_tmp/dev-tls"
PATH="$fake_bin" \
  VXPIPE_TEST_GOREMAN_ARGS="$goreman_args" \
  VXPIPE_TEST_DEV_TLS="$dev_tls" \
  "$repo_root/bin/dev"

assert_file_has_line "$dev_tls" "http"
assert_file_has_line "$goreman_args" "start"
assert_file_has_line "$goreman_args" "vxpipe"
assert_file_has_line "$goreman_args" "reloader"
assert_file_has_line "$goreman_args" "docs"
assert_file_lacks_line "$goreman_args" "assets"
assert_file_lacks_line "$goreman_args" "caddy"

assert_file_has_line "$repo_root/Procfile" "reloader: bin/watch-vxpipe"
assert_file_has_line "$repo_root/Procfile" "docs: env ASTRO_DEV_BACKGROUND=0 npm --prefix vxpipe-docs run dev"
assert_file_lacks_line "$repo_root/Procfile" "caddy: bin/run-caddy"

if output="$(PATH="$fake_bin" "$repo_root/bin/dev" --tailscale 2>&1)"; then
  fail "expected --tailscale to reject a missing tailscale executable"
fi
assert_output_contains "$output" "Error: bin/dev --tailscale requires tailscale on PATH."

for invalid_args in "--http" "--https" "--tailscale unexpected"; do
  read -r -a invalid_argv <<<"$invalid_args"
  if output="$(PATH="$fake_bin" \
    VXPIPE_TEST_GOREMAN_ARGS="$goreman_args" \
    VXPIPE_TEST_DEV_TLS="$dev_tls" \
    "$repo_root/bin/dev" "${invalid_argv[@]}" 2>&1)"; then
    fail "expected bin/dev to reject invalid arguments: $invalid_args"
  fi
  assert_output_contains "$output" "Usage: bin/dev [--tailscale]"
done

make_executable tailscale \
  'case "${1:-}" in' \
  '  status)' \
  '    printf '\''%s\n'\'' '\''{"Self":{"DNSName":"console.example.ts.net.","TailscaleIPs":["100.64.0.12","fd7a:115c:a1e0::12"]}}'\''' \
  '    ;;' \
  '  cert)' \
  '    printf '\''%s\n'\'' "$@" >>"$VXPIPE_TEST_TAILSCALE_CERT_ARGS"' \
  '    ;;' \
  'esac'

if output="$(PATH="$fake_bin" "$repo_root/bin/dev" --tailscale 2>&1)"; then
  fail "expected --tailscale to reject a missing jq executable"
fi
assert_output_contains "$output" "Error: bin/dev --tailscale requires jq on PATH."

ln -s "$(command -v jq)" "$fake_bin/jq"
ln -s "$(command -v mkdir)" "$fake_bin/mkdir"
ln -s "$(command -v chmod)" "$fake_bin/chmod"
ln -s "$(command -v mktemp)" "$fake_bin/mktemp"
ln -s "$(command -v mv)" "$fake_bin/mv"
ln -s "$(command -v rm)" "$fake_bin/rm"
make_executable goreman \
  'printf "%s\n" "$@" >"$VXPIPE_TEST_GOREMAN_ARGS"' \
  'if [[ -n "${VXPIPE_TEST_TLS_ENV:-}" ]]; then' \
  '  printf "%s\n" "$APP_HOST" "$VXPIPE_DEV_TLS_CERTFILE" "$VXPIPE_DEV_TLS_KEYFILE" "$VXPIPE_TAILSCALE_IP" "$VXPIPE_DEV_TLS" >"$VXPIPE_TEST_TLS_ENV"' \
  'fi'

https_args="$test_tmp/https-args"
tailscale_cert_args="$test_tmp/tailscale-cert-args"
tls_env="$test_tmp/tls-env"
PATH="$fake_bin" \
  VXPIPE_TEST_GOREMAN_ARGS="$https_args" \
  VXPIPE_TEST_TAILSCALE_CERT_ARGS="$tailscale_cert_args" \
  VXPIPE_TEST_TLS_ENV="$tls_env" \
  "$repo_root/bin/dev" --tailscale

assert_file_has_line "$https_args" "start"
assert_file_has_line "$https_args" "vxpipe"
assert_file_has_line "$https_args" "reloader"
assert_file_has_line "$https_args" "docs"
assert_file_lacks_line "$https_args" "caddy"
[[ "$(sed -n '1p' "$tls_env")" == "console.example.ts.net" ]] ||
  fail "expected bin/dev to derive APP_HOST from Tailscale"
[[ "$(sed -n '2p' "$tls_env")" == "$repo_root/tmp/tls/console.example.ts.net.crt" ]] ||
  fail "expected bin/dev to configure Phoenix's TLS certificate path"
[[ "$(sed -n '3p' "$tls_env")" == "$repo_root/tmp/tls/console.example.ts.net.key" ]] ||
  fail "expected bin/dev to configure Phoenix's TLS key path"
[[ "$(sed -n '4p' "$tls_env")" == "100.64.0.12" ]] ||
  fail "expected bin/dev to bind Phoenix to the Tailscale IPv4 address"
assert_file_has_line "$tls_env" "phoenix"
assert_file_has_line "$tailscale_cert_args" "cert"
assert_file_has_line "$tailscale_cert_args" "--cert-file"
assert_file_has_line "$tailscale_cert_args" "-"
assert_file_has_line "$tailscale_cert_args" "--key-file"
assert_file_has_line "$tailscale_cert_args" "console.example.ts.net"

make_executable watchman-make \
  'printf "%s\n" "$PWD" >"$VXPIPE_TEST_WATCHMAN_CWD"' \
  'printf "%s\n" "$@" >"$VXPIPE_TEST_WATCHMAN_ARGS"'

watchman_args="$test_tmp/watchman-args"
watchman_cwd="$test_tmp/watchman-cwd"
PATH="$fake_bin" \
  VXPIPE_TEST_WATCHMAN_ARGS="$watchman_args" \
  VXPIPE_TEST_WATCHMAN_CWD="$watchman_cwd" \
  "$repo_root/bin/watch-vxpipe"

[[ "$(<"$watchman_cwd")" == "$repo_root" ]] ||
  fail "expected Watchman to run from the repository root"
assert_file_has_line "$watchman_args" "apps/*/lib/**/*.ex"
assert_file_has_line "$watchman_args" "apps/*/mix.exs"
assert_file_has_line "$watchman_args" "config/*.exs"
assert_file_has_line "$watchman_args" "mix.exs"
assert_file_has_line "$watchman_args" "mix.lock"
assert_file_has_line "$watchman_args" "--run"
assert_file_has_line "$watchman_args" "bin/restart-vxpipe"

restart_args="$test_tmp/restart-args"
PATH="$fake_bin" \
  VXPIPE_TEST_GOREMAN_ARGS="$restart_args" \
  "$repo_root/bin/restart-vxpipe"

[[ "$(<"$restart_args")" == $'run\nrestart\nvxpipe' ]] ||
  fail "expected restart helper to delegate to goreman run restart vxpipe"

echo "bin/dev process integration tests passed"
