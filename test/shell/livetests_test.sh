#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d -t vxpipe-live-providers.XXXXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

mkdir -p "$scratch/bin"
cat > "$scratch/bin/mix" <<'MIX'
#!/usr/bin/env bash
if [[ "$1" == run ]]; then
  printf 'argument=%s\n' "$@" > "$VXPIPE_LIVE_RUNNER_TEST_OUTPUT"
  exit 0
fi
{
  printf 'directory=%s\n' "$PWD"
  printf 'runner=%s\n' "${VXPIPE_LIVETESTS_RUNNER:-missing}"
  printf 'openai=%s\n' "${OPENAI_API_KEY:-missing}"
  printf 'gemini=%s\n' "${GEMINI_API_KEY:-missing}"
  for name in DEEPSEEK_API_KEY OPENROUTER_API_KEY FIREWORKS_API_KEY CARTESIA_API_KEY ELEVENLABS_API_KEY; do
    printf '%s=%s\n' "$name" "${!name:-missing}"
  done
  printf 'telnyx=%s\n' "${TELNYX_API_KEY:-missing}"
  printf 'telephony_url=%s\n' "${TELEPHONY_TEST_PUBLIC_URL:-missing}"
  printf 'telnyx_public_key=%s\n' "${TELNYX_PUBLIC_KEY:-missing}"
  printf 'tailscale_secret=%s\n' "${TAILSCALE_CLIENT_SECRET:-missing}"
  printf 'argument=%s\n' "$@"
} > "$VXPIPE_LIVE_RUNNER_TEST_OUTPUT"
MIX
chmod +x "$scratch/bin/mix"

cat > "$scratch/live_providers.env" <<'ENV'
DEEPSEEK_API_KEY=test-deepseek
OPENROUTER_API_KEY=test-openrouter
FIREWORKS_API_KEY=todo
CARTESIA_API_KEY=todo
ELEVENLABS_API_KEY=test-elevenlabs
OPENAI_API_KEY=test-only-key
GEMINI_API_KEY=todo
TELNYX_API_KEY=todo
TELEPHONY_TEST_PUBLIC_URL=https://todo
ENV

export VXPIPE_LIVETESTS_STATE_DIR="$scratch/state"
export VXPIPE_LIVE_RUNNER_TEST_OUTPUT="$scratch/output"
export VXPIPE_LIVE_PROVIDERS_ENV_FILE="$scratch/live_providers.env"
export VXPIPE_LIVE_PROVIDERS_MIX_BIN="$scratch/bin/mix"
export TELNYX_API_KEY=ambient-test-only-key
export TELNYX_PUBLIC_KEY=ambient-test-only-key
export TAILSCALE_CLIENT_SECRET=ambient-test-only-key
export FIREWORKS_API_KEY=ambient-test-only-key
export CARTESIA_API_KEY=ambient-test-only-key
export ELEVENLABS_API_KEY=ambient-test-only-key

"$repo_root/bin/livetests" run --only live_openai \
  apps/vxpipe_call_engine/test/integration/gpt_live_hosted_test.exs

rg -q -F "directory=$repo_root" "$scratch/output"
rg -q -F 'runner=1' "$scratch/output"
rg -q -F 'openai=test-only-key' "$scratch/output"
rg -q -F 'DEEPSEEK_API_KEY=test-deepseek' "$scratch/output"
rg -q -F 'OPENROUTER_API_KEY=test-openrouter' "$scratch/output"
for name in FIREWORKS_API_KEY CARTESIA_API_KEY; do
  if ! rg -q -F "$name=missing" "$scratch/output"; then
    printf '%s placeholder was not cleared\n' "$name" >&2
    exit 1
  fi
done
rg -q -F 'ELEVENLABS_API_KEY=test-elevenlabs' "$scratch/output"
rg -q -F 'gemini=missing' "$scratch/output"
rg -q -F 'telnyx=missing' "$scratch/output"
rg -q -F 'telephony_url=missing' "$scratch/output"
rg -q -F 'telnyx_public_key=missing' "$scratch/output"
rg -q -F 'tailscale_secret=missing' "$scratch/output"
rg -q -F 'argument=--only' "$scratch/output"
rg -q -F 'argument=live_openai' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_call_engine/test/integration/gpt_live_hosted_test.exs' "$scratch/output"

# A configured public URL keeps the default all-provider run off Tailscale.
cat > "$scratch/live_providers.env" <<'ENV'
OPENAI_API_KEY=test-only-key
TELEPHONY_TEST_PUBLIC_URL=https://voice.example.test
ENV

"$repo_root/bin/livetests" run
for name in CARTESIA_API_KEY ELEVENLABS_API_KEY; do
  if ! rg -q -F "$name=missing" "$scratch/output"; then
    printf '%s leaked from the ambient environment\n' "$name" >&2
    exit 1
  fi
done
rg -q -F 'argument=live_providers' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_agent_runtime/test/integration' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_call_engine/test/integration' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_gateway/test/integration' "$scratch/output"
rg -q -F 'argument=apps/vxpipe_console/test/integration' "$scratch/output"
if rg -q -F 'apps/vxpipe_artifacts/test/integration' "$scratch/output"; then
  printf 'storage tests entered the live provider lane\n' >&2
  exit 1
fi

rm -- "$scratch/live_providers.env"
if "$repo_root/bin/livetests" run --only live_openai > "$scratch/stdout" 2> "$scratch/stderr"; then
  printf 'missing credential file unexpectedly succeeded\n' >&2
  exit 1
fi
rg -q -F 'live_providers.env.example' "$scratch/stderr"

# Decisions loads the named installation connection even without a live provider file.
for provider in openai google jev; do
  "$repo_root/bin/livetests" decisions "$provider" DemoTenant000001 billing-policy
  rg -qxF 'argument=run' "$scratch/output"
  rg -qxF 'argument=--no-start' "$scratch/output"
  rg -qxF "argument=$provider" "$scratch/output"
  rg -qxF 'argument=DemoTenant000001' "$scratch/output"
  rg -qxF 'argument=billing-policy' "$scratch/output"
done
if "$repo_root/bin/livetests" decisions openai > "$scratch/stdout" 2> "$scratch/stderr"; then
  echo 'Decisions must require an explicit tenant and connection' >&2
  exit 1
fi
rg -q 'TENANT.*CONNECTION' "$scratch/stderr"

if "$repo_root/bin/livetests" run --only live_openai_decisions > "$scratch/stdout" 2> "$scratch/stderr"; then
  echo 'Obsolete Decisions tags must direct the caller to the configured runner' >&2
  exit 1
fi
rg -q 'decisions openai TENANT CONNECTION' "$scratch/stderr"

# Subcommand dispatch
"$repo_root/bin/livetests" help > "$scratch/help"
rg -q -F 'run' "$scratch/help"

for arguments in "" "unknown-subcommand"; do
  # shellcheck disable=SC2086
  if "$repo_root/bin/livetests" $arguments > "$scratch/stdout" 2> "$scratch/stderr"; then
    printf 'livetests %s unexpectedly succeeded\n' "${arguments:-<none>}" >&2
    exit 1
  fi
  rg -q -F 'Usage: bin/livetests' "$scratch/stderr"
done

if [[ -e "$repo_root/bin/test-live-providers" ]]; then
  printf 'bin/test-live-providers should be replaced by bin/livetests\n' >&2
  exit 1
fi

printf 'livetests checks passed\n'
