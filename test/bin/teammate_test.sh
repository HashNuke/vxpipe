#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/opencode" <<'FAKE_OPENCODE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$VXPIPE_TEST_ARGS"
cat >"$VXPIPE_TEST_STDIN"
FAKE_OPENCODE
chmod +x "$fake_bin/opencode"

assert_line() {
  local file="$1" expected="$2"
  grep -Fx -- "$expected" "$file" >/dev/null || {
    echo "expected $file to contain: $expected" >&2
    exit 1
  }
}

default_args="$test_tmp/default-args"
default_stdin="$test_tmp/default-stdin"
PATH="$fake_bin:$PATH" \
  VXPIPE_TEST_ARGS="$default_args" \
  VXPIPE_TEST_STDIN="$default_stdin" \
  "$repo_root/bin/teammate" "Fix the failing test"
assert_line "$default_args" "run"
assert_line "$default_args" "--auto"
assert_line "$default_args" "--model"
assert_line "$default_args" "opencode-go/muse-spark-1.3-contributor"
assert_line "$default_args" "Fix the failing test"

override_args="$test_tmp/override-args"
override_stdin="$test_tmp/override-stdin"
printf '%s\n' "Review this piped task" | \
  PATH="$fake_bin:$PATH" \
  VXPIPE_TEST_ARGS="$override_args" \
  VXPIPE_TEST_STDIN="$override_stdin" \
  "$repo_root/bin/teammate" --model custom/provider-model
assert_line "$override_args" "--model"
assert_line "$override_args" "custom/provider-model"
assert_line "$override_args" "Review this piped task"

echo "teammate script tests passed"
