#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d -t vxpipe-livetests-tools.XXXXXXXX)"
cleanup() {
  local pid
  for pid in $(cat "$scratch"/fake-ts/*/tailscaled.pid 2>/dev/null); do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf -- "$scratch"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$scratch/bin" "$scratch/fake-ts"

# Fake tailscaled: stays alive until terminated, like the real daemon.
cat > "$scratch/bin/tailscaled" <<'FAKE'
#!/usr/bin/env bash
socket=""
for argument in "$@"; do
  case "$argument" in --socket=*) socket="${argument#--socket=}" ;; esac
done
node_dir="$FAKE_TS_DIR/$(printf '%s' "$socket" | md5sum | cut -c1-12)"
mkdir -p "$node_dir"
printf '%s\n' "$$" > "$node_dir/tailscaled.pid"
printf 'tailscaled %s\n' "$*" >> "$FAKE_TS_DIR/log"
[[ -f "$node_dir/registered" ]] && echo Stopped > "$node_dir/backend" || echo NeedsLogin > "$node_dir/backend"
trap 'rm -f "$node_dir/tailscaled.pid"; exit 0' TERM INT
while :; do sleep 0.1; done
FAKE

# Fake tailscale CLI: keeps per-socket node state under FAKE_TS_DIR.
cat > "$scratch/bin/tailscale" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
socket=""
if [[ "${1:-}" == --socket=* ]]; then
  socket="${1#--socket=}"
  shift
elif [[ "$*" == "status --json" ]]; then
  echo '{"MagicDNSSuffix":"tail0000.ts.net"}'
  exit 0
fi
node_dir="$FAKE_TS_DIR/$(printf '%s' "$socket" | md5sum | cut -c1-12)"
printf 'tailscale %s\n' "$*" >> "$FAKE_TS_DIR/log"
[[ -f "$node_dir/tailscaled.pid" ]] || { echo "failed to connect to local tailscaled" >&2; exit 1; }
dns() { cat "$node_dir/dns" 2>/dev/null || true; }
case "$1 ${2:-}" in
  "status --json")
    printf '{"BackendState":"%s","Self":{"DNSName":"%s"}}\n' "$(cat "$node_dir/backend")" "$(dns)"
    ;;
  "up "*|"up")
    shift
    for argument in "$@"; do
      case "$argument" in
        --hostname=*) hostname="${argument#--hostname=}" ;;
        --auth-key=file:*) printf 'authkey=%s\n' "$(cat "${argument#--auth-key=file:}")" >> "$FAKE_TS_DIR/log" ;;
      esac
    done
    if [[ ! -f "$node_dir/registered" ]]; then
      grep -q -- '--auth-key=' <<< "$*" || { echo "needs login" >&2; exit 1; }
      printf '%s%s.tail0000.ts.net.\n' "$hostname" "${FAKE_TS_NAME_SUFFIX:-}" > "$node_dir/dns"
      touch "$node_dir/registered"
    fi
    echo Running > "$node_dir/backend"
    ;;
  "funnel status")
    if [[ -f "$node_dir/funnel" ]]; then
      printf '{"Web":{"%s:443":{"Handlers":{"/":{"Proxy":"%s"}}}}}\n' "$(dns | sed 's/\.$//')" "$(cat "$node_dir/funnel")"
    else
      echo '{}'
    fi
    ;;
  "funnel --bg")
    printf '%s\n' "${@: -1}" > "$node_dir/funnel"
    ;;
  "funnel --https=443")
    [[ "${@: -1}" == off ]] && rm -f "$node_dir/funnel"
    ;;
  *) echo "unexpected tailscale call: $*" >&2; exit 1 ;;
esac
FAKE

# Fake curl: an already provisioned carrier account for this machine.
cat > "$scratch/bin/curl" <<'FAKE'
#!/usr/bin/env bash
url="${*: -1}"
cat > /dev/null
# Public DNS returns three Funnel relays; FAKE_SLOW_RELAY stays unreachable for
# FAKE_RELAY_WARMUP probes. A reachable relay answers 502 (nothing listens yet).
case "$url" in
  https://dns.google/resolve*)
    echo '{"Answer":[{"type":1,"data":"192.0.2.1"},{"type":1,"data":"192.0.2.2"},{"type":1,"data":"192.0.2.3"}]}'
    exit 0 ;;
  */healthz)
    relay="$(printf '%s\n' "$@" | sed -n 's/^.*:443:\(.*\)$/\1/p')"
    count=$(( $(cat "$FAKE_TS_DIR/relay-$relay" 2>/dev/null || echo 0) + 1 ))
    echo "$count" > "$FAKE_TS_DIR/relay-$relay"
    if [[ "$relay" == "${FAKE_SLOW_RELAY:-}" && "$count" -le "${FAKE_RELAY_WARMUP:-0}" ]]; then
      printf '000'; exit 28
    fi
    printf '502'; exit 0 ;;
esac
base="https://vxp-test-$FAKE_MACHINE.tail0000.ts.net"
case "$url" in
  *outbound_voice_profiles*) body="{\"data\":[{\"id\":\"p1\",\"name\":\"vxp-test-$FAKE_MACHINE\"}]}" ;;
  *call_control_applications*) body="{\"data\":[{\"id\":\"a1\",\"application_name\":\"vxp-test-$FAKE_MACHINE\",\"webhook_event_url\":\"$base/webhooks/platform/telnyx\",\"outbound\":{\"outbound_voice_profile_id\":\"p1\"}}]}" ;;
  *phone_numbers*filter*tag*-b) body="{\"data\":[{\"id\":\"n2\",\"phone_number\":\"+13125550143\",\"connection_id\":\"a1\",\"tags\":[\"vxp-test-$FAKE_MACHINE-b\"]}]}" ;;
  *phone_numbers*) body="{\"data\":[{\"id\":\"n1\",\"phone_number\":\"+13125550142\",\"connection_id\":\"a1\",\"tags\":[\"vxp-test-$FAKE_MACHINE\"]}]}" ;;
  *IncomingPhoneNumbers*) body="{\"incoming_phone_numbers\":[{\"sid\":\"PN1\",\"phone_number\":\"+14155550199\",\"friendly_name\":\"vxp-test-$FAKE_MACHINE\",\"voice_url\":\"$base/api/telephony/twilio/vxp-test-twilio/voice\",\"voice_method\":\"POST\"}]}" ;;
  *) echo "unexpected $url" >&2; exit 7 ;;
esac
printf '%s\n200' "$body"
FAKE

# Fake mix: records the telephony environment and the live Funnel target.
cat > "$scratch/bin/mix" <<'MIX'
#!/usr/bin/env bash
{
  printf 'public_url=%s\n' "${TELEPHONY_TEST_PUBLIC_URL:-missing}"
  printf 'port=%s\n' "${TELEPHONY_TEST_PORT:-missing}"
  printf 'funnel=%s\n' "$(cat "$FAKE_TS_DIR"/*/funnel 2>/dev/null || echo none)"
  printf 'secret=%s\n' "${TAILSCALE_CLIENT_SECRET:-missing}"
} > "$VXPIPE_LIVE_RUNNER_TEST_OUTPUT"
exit "${FAKE_MIX_STATUS:-0}"
MIX
chmod +x "$scratch/bin/"*

export FAKE_TS_DIR="$scratch/fake-ts"
export VXPIPE_LIVE_RUNNER_TEST_OUTPUT="$scratch/output"
export VXPIPE_LIVE_PROVIDERS_ENV_FILE="$scratch/live_providers.env"
export VXPIPE_LIVE_PROVIDERS_MIX_BIN="$scratch/bin/mix"
export VXPIPE_LIVETESTS_TAILSCALE_BIN="$scratch/bin/tailscale"
export VXPIPE_LIVETESTS_TAILSCALED_BIN="$scratch/bin/tailscaled"
export VXPIPE_LIVETESTS_STATE_DIR="$scratch/state"
export VXP_TEST_MACHINE="Wheel_Jack.local"
export FAKE_MACHINE=wheel-jack-local
export VXPIPE_LIVETESTS_CURL_BIN="$scratch/bin/curl"
export VXPIPE_LIVETESTS_RELAY_INTERVAL=0.05
unset TELEPHONY_TEST_PUBLIC_URL TELEPHONY_TEST_PORT

carriers='TELNYX_API_KEY=KEYtestonly
TWILIO_ACCOUNT_SID=ACtestonly
TWILIO_AUTH_TOKEN=token-test-only'
cat > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE" <<ENV
$carriers
TAILSCALE_CLIENT_SECRET=tskey-client-test-only
TELEPHONY_TEST_PUBLIC_URL=https://todo
ENV

livetests() { "$repo_root/bin/livetests" "$@"; }
log_has() { rg -q -F -- "$1" "$FAKE_TS_DIR/log"; }
tailscaled_running() { compgen -G "$FAKE_TS_DIR/*/tailscaled.pid" > /dev/null; }

# A telephony selection without carrier credentials runs tests without tooling.
printf 'TAILSCALE_CLIENT_SECRET=tskey-client-test-only\n' > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
livetests run --only live_telephony apps/vxpipe_console/test/integration
[[ ! -e "$FAKE_TS_DIR/log" ]] || fail "run without carrier credentials called tailscale"
printf '%s\nTAILSCALE_CLIENT_SECRET=tskey-client-test-only\n' "$carriers" > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"

# A non-telephony selection never touches Tailscale.
livetests run --only live_openai apps/vxpipe_call_engine/test/integration
[[ ! -e "$FAKE_TS_DIR/log" ]] || fail "non-telephony run called tailscale"
rg -q -F 'public_url=missing' "$scratch/output" || fail "non-telephony run exported a public URL"

# A telephony run registers the machine node, funnels 443 during the test and
# tears down only what it started.
FAKE_MIX_STATUS=3 livetests run --only live_telephony apps/vxpipe_console/test/integration \
  && fail "run did not propagate the mix exit status" || [[ $? -eq 3 ]] || fail "wrong exit status"
rg -q -F 'public_url=https://vxp-test-wheel-jack-local.tail0000.ts.net' "$scratch/output" \
  || fail "public URL not derived from the machine node"
rg -q -F 'port=4600' "$scratch/output" || fail "default test port not exported"
rg -q -F 'funnel=http://127.0.0.1:4600' "$scratch/output" || fail "funnel not up during the test"
log_has 'tailscaled --tun=userspace-networking' || fail "tailscaled not in userspace mode"
log_has '--hostname=vxp-test-wheel-jack-local' || fail "node hostname not derived"
log_has '--advertise-tags=tag:vxp-test' || fail "tag not advertised"
log_has 'authkey=tskey-client-test-only?ephemeral=false&preauthorized=true' \
  || fail "OAuth secret not registered as non-ephemeral and preauthorized"
if rg -q -F -- '--auth-key=tskey' "$FAKE_TS_DIR/log"; then fail "secret passed on the command line"; fi
tailscaled_running && fail "run left tailscaled running"
[[ -z "$(find "$scratch/state" -name '*authkey*')" ]] || fail "auth key file left behind"

# A later run reuses the registration without needing the secret again.
: > "$FAKE_TS_DIR/log"
printf '%s\nTELEPHONY_TEST_PUBLIC_URL=https://todo\n' "$carriers" > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
livetests run --only live_twilio apps/vxpipe_gateway/test/integration
rg -q -F 'funnel=http://127.0.0.1:4600' "$scratch/output" || fail "registered node not reused"
log_has 'authkey=' && fail "registered node asked for the secret again"
tailscaled_running && fail "second run left tailscaled running"

# Piped output must end when tools:up does; the daemon may not hold the pipe open.
if ! timeout 20 bash -c '"$0" tools:up 2>&1 | cat > /dev/null' "$repo_root/bin/livetests"; then
  fail "tools:up output pipe stayed open after it returned"
fi
livetests tools:down > /dev/null

# Narrower telephony tags (live_telephony_*) also start the public endpoint.
: > "$FAKE_TS_DIR/log"
livetests run --only live_telephony_sts apps/vxpipe_console/test/integration
rg -q -F 'funnel=http://127.0.0.1:4600' "$scratch/output" || fail "live_telephony_* selection did not start the tools"
tailscaled_running && fail "live_telephony_* run left tailscaled running"

# tools:up waits until every public Funnel relay answers, since carriers may reach any.
FAKE_SLOW_RELAY=192.0.2.3 FAKE_RELAY_WARMUP=2 livetests tools:up > "$scratch/up"
[[ "$(cat "$FAKE_TS_DIR/relay-192.0.2.3" 2>/dev/null || echo 0)" -ge 3 ]] \
  || fail "tools:up did not wait for a slow relay"
for relay in 192.0.2.1 192.0.2.2; do
  [[ -s "$FAKE_TS_DIR/relay-$relay" ]] || fail "relay $relay was not probed"
done
livetests tools:down > /dev/null

# A relay that never answers fails within the bound, names it, and run cleans up.
rm -f "$FAKE_TS_DIR"/relay-*
if FAKE_SLOW_RELAY=192.0.2.3 FAKE_RELAY_WARMUP=100000 VXPIPE_LIVETESTS_RELAY_TIMEOUT=1 \
  livetests run --only live_telephony apps/vxpipe_console/test/integration 2> "$scratch/stderr"; then
  fail "run dialed with an unreachable public relay"
fi
rg -q -F '192.0.2.3' "$scratch/stderr" || fail "unreachable relay not named"
tailscaled_running && fail "run left tailscaled running after a relay failure"

# Tools started by tools:up stay up after a run; tools:down stops them.
livetests tools:up > "$scratch/up"
rg -q -F 'https://vxp-test-wheel-jack-local.tail0000.ts.net' "$scratch/up" || fail "tools:up did not print the URL"
livetests run --only live_telnyx apps/vxpipe_gateway/test/integration
tailscaled_running || fail "run stopped tools it did not start"
livetests tools:status > "$scratch/status"
rg -q -F 'vxp-test-wheel-jack-local' "$scratch/status" || fail "tools:status missing node"
rg -q -F 'http://127.0.0.1:4600' "$scratch/status" || fail "tools:status missing funnel target"

# Per-run teardown leaves the branch reservation intact.
[[ "$(cat "$scratch/state/owner")" == "$(git -C "$repo_root" symbolic-ref --short HEAD)" ]] || fail "branch ownership lost"
[[ -z "$(find "$scratch/state" -name lock)" ]] || fail "obsolete process lock remains"

livetests tools:down
tailscaled_running && fail "tools:down left tailscaled running"
[[ -z "$(cat "$FAKE_TS_DIR"/*/funnel 2>/dev/null)" ]] || fail "tools:down left the funnel mapping"

# An existing 443 mapping to another target is refused and left untouched.
livetests tools:up > /dev/null
node_dir="$(dirname "$(compgen -G "$FAKE_TS_DIR/*/tailscaled.pid")")"
printf 'http://127.0.0.1:9999\n' > "$node_dir/funnel"
livetests tools:down > /dev/null || true
printf 'http://127.0.0.1:9999\n' > "$node_dir/funnel"
if livetests tools:up 2> "$scratch/stderr"; then fail "foreign funnel mapping replaced"; fi
rg -q -F 'already serves' "$scratch/stderr" || fail "foreign mapping refusal not explained"
[[ "$(cat "$node_dir/funnel")" == "http://127.0.0.1:9999" ]] || fail "foreign mapping changed"
livetests tools:down > /dev/null || true

# A configured public URL disables Tailscale management entirely.
: > "$FAKE_TS_DIR/log"
printf '%s\nTELEPHONY_TEST_PUBLIC_URL=https://vxp-test-wheel-jack-local.tail0000.ts.net\n' "$carriers" > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
livetests run --only live_telephony apps/vxpipe_console/test/integration
rg -q -F 'public_url=https://vxp-test-wheel-jack-local.tail0000.ts.net' "$scratch/output" || fail "override not exported"
[[ ! -s "$FAKE_TS_DIR/log" ]] || fail "override run called tailscale"

# Registration without a secret explains what is missing.
rm -rf "$scratch/state" "$FAKE_TS_DIR"/*/registered
export VXP_TEST_MACHINE=fresh
printf '\n' > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
if livetests tools:up 2> "$scratch/stderr"; then fail "registration without a secret succeeded"; fi
rg -q -F 'TAILSCALE_CLIENT_SECRET' "$scratch/stderr" || fail "missing secret not named"
livetests tools:down > /dev/null 2>&1 || true

# A node renamed by a stale registration is reported, not silently used.
rm -rf "$scratch/state"
export VXP_TEST_MACHINE=stale
printf 'TAILSCALE_CLIENT_SECRET=tskey-client-test-only\n' > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
if FAKE_TS_NAME_SUFFIX=-1 livetests tools:up 2> "$scratch/stderr"; then fail "renamed node accepted"; fi
rg -q -F 'vxp-test-stale-1' "$scratch/stderr" || fail "renamed node not reported"
livetests tools:down > /dev/null 2>&1 || true

printf 'livetests tools checks passed\n'
