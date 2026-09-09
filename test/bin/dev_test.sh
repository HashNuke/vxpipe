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

mkdir -p "$fake_bin"
ln -s "$(command -v bash)" "$fake_bin/bash"
ln -s "$(command -v dirname)" "$fake_bin/dirname"
make_executable goreman 'exit 0'
make_executable npm 'exit 0'

if output="$(PATH="$fake_bin" "$repo_root/bin/dev" --http 2>&1)"; then
  fail "expected bin/dev to reject a missing watchman executable"
fi

assert_output_contains "$output" "Error: bin/dev requires watchman on PATH."

make_executable watchman 'exit 0'

if output="$(PATH="$fake_bin" "$repo_root/bin/dev" --http 2>&1)"; then
  fail "expected bin/dev to reject a missing watchman-make executable"
fi

assert_output_contains "$output" "Error: bin/dev requires watchman-make on PATH."

make_executable watchman-make 'exit 0'
make_executable goreman 'printf "%s\n" "$@" >"$VXPIPE_TEST_GOREMAN_ARGS"'

goreman_args="$test_tmp/goreman-args"
PATH="$fake_bin" \
  VXPIPE_TEST_GOREMAN_ARGS="$goreman_args" \
  "$repo_root/bin/dev" --http

assert_file_has_line "$goreman_args" "start"
assert_file_has_line "$goreman_args" "vxpipe"
assert_file_has_line "$goreman_args" "assets"
assert_file_has_line "$goreman_args" "reloader"

assert_file_has_line "$repo_root/Procfile" "reloader: bin/watch-vxpipe"

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

echo "bin/dev Watchman integration tests passed"
