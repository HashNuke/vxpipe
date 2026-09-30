#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d -t vxpipe-live-providers.XXXXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

mkdir -p "$scratch/bin"
cat > "$scratch/bin/mix" <<'MIX'
#!/usr/bin/env bash
{
  printf 'directory=%s\n' "$PWD"
  printf 'openai=%s\n' "${OPENAI_API_KEY:-missing}"
  printf 'gemini=%s\n' "${GEMINI_API_KEY:-missing}"
  for name in DEEPSEEK_API_KEY OPENROUTER_API_KEY FIREWORKS_API_KEY; do
    printf '%s=%s\n' "$name" "${!name:-missing}"
  done
  printf 'telnyx=%s\n' "${TELNYX_API_KEY:-missing}"
  printf 'webhook=%s\n' "${TELNYX_TEST_WEBHOOK_URL:-missing}"
  printf 'argument=%s\n' "$@"
} > "$VXPIPE_LIVE_RUNNER_TEST_OUTPUT"
MIX
chmod +x "$scratch/bin/mix"

cat > "$scratch/live_providers.env" <<'ENV'
DEEPSEEK_API_KEY=test-deepseek
OPENROUTER_API_KEY=test-openrouter
FIREWORKS_API_KEY=todo
OPENAI_API_KEY=test-only-key
GEMINI_API_KEY=todo
TELNYX_API_KEY=todo
TELNYX_TEST_WEBHOOK_URL=https://todo
ENV

export VXPIPE_LIVE_RUNNER_TEST_OUTPUT="$scratch/output"
export VXPIPE_LIVE_PROVIDERS_ENV_FILE="$scratch/live_providers.env"
export VXPIPE_LIVE_PROVIDERS_MIX_BIN="$scratch/bin/mix"
export TELNYX_API_KEY=ambient-test-only-key
export FIREWORKS_API_KEY=ambient-test-only-key

"$repo_root/bin/test-live-providers" --only live_openai \
  apps/vxpipe_call_engine/test/integration/gpt_live_hosted_test.exs

rg -q -F "directory=$repo_root" "$scratch/output"
rg -q -F 'openai=test-only-key' "$scratch/output"
rg -q -F 'DEEPSEEK_API_KEY=test-deepseek' "$scratch/output"
rg -q -F 'OPENROUTER_API_KEY=test-openrouter' "$scratch/output"
for name in FIREWORKS_API_KEY; do
  rg -q -F "$name=missing" "$scratch/output"
done
rg -q -F 'gemini=missing' "$scratch/output"
rg -q -F 'telnyx=missing' "$scratch/output"
rg -q -F 'webhook=missing' "$scratch/output"
rg -q -F 'argument=--only' "$scratch/output"
rg -q -F 'argument=live_openai' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_call_engine/test/integration/gpt_live_hosted_test.exs' "$scratch/output"

"$repo_root/bin/test-live-providers"
rg -q -F 'argument=live_providers' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_agent_runtime/test/integration' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_call_engine/test/integration' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_gateway/test/integration' "$scratch/output"
if rg -q -F 'apps/vxpipe_artifacts/test/integration' "$scratch/output"; then
  printf 'storage tests entered the live provider lane\n' >&2
  exit 1
fi

rm -- "$scratch/live_providers.env"
if "$repo_root/bin/test-live-providers" --only live_openai > "$scratch/stdout" 2> "$scratch/stderr"; then
  printf 'missing credential file unexpectedly succeeded\n' >&2
  exit 1
fi
rg -q -F 'live_providers.env.example' "$scratch/stderr"

printf 'live provider runner checks passed\n'
