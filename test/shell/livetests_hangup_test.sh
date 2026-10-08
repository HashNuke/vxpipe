#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d -t vxpipe-livetests-hangup.XXXXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$scratch/bin" "$scratch/api"

# Provider state changes immediately when calls end, so mutating before fetching
# every page would skip calls. Small pages exercise both providers' pagination.
cat > "$scratch/bin/curl" <<'FAKE'
#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

api = Path(os.environ['FAKE_API_DIR'])
args = sys.argv[1:]
config = sys.stdin.read()
assert args[args.index('--connect-timeout') + 1] == '10'
assert args[args.index('--max-time') + 1] == '30'
with (api / 'log').open('a') as log:
    log.write('ARGV ' + json.dumps(args) + '\n')
    log.write('CONFIG ' + config.strip() + '\n')

def reply(code, body):
    print(json.dumps(body) + '\n' + str(code), end='')
    sys.exit(0)

def read(name):
    return json.loads((api / name).read_text())

def save(name, value):
    (api / name).write_text(json.dumps(value))

method = args[args.index('-X') + 1]
url = urlparse(args[-1])
query = parse_qs(url.query)
path = unquote(url.path)
provider = 'telnyx' if url.hostname == 'api.telnyx.com' else 'twilio'
if provider == 'telnyx':
    assert 'Authorization: Bearer KEYtestonly' in config
else:
    assert 'ACtestonly:twilio-token-test-only' in config

if (api / (provider + '-transport-error')).exists():
    sys.exit(7)
if method == 'GET' and (api / (provider + '-list-error')).exists():
    reply(401, {'message': 'ACtestonly twilio-token-test-only KEYtestonly'})
if method == 'GET' and (api / (provider + '-malformed')).exists():
    reply(200, {})

if method == 'GET' and path == '/v2/call_control_applications':
    apps = read('apps.json')
    page = int(query.get('page[number]', ['1'])[0])
    reply(200, {'data': apps[page - 1:page], 'meta': {'total_pages': len(apps), 'page_number': page}})

if method == 'GET' and path.startswith('/v2/connections/'):
    connection = path.split('/')[3]
    calls = [c for c in read('telnyx.json') if c['connection_id'] == connection and c['active']]
    if 'page[after]' in query:
        calls = [c for c in calls if c['call_control_id'] > query['page[after]'][0]]
    next_path = None
    if len(calls) > 1:
        next_path = path + '?page[after]=' + calls[0]['call_control_id']
    if (api / 'telnyx-bad-next').exists():
        next_path = '/v2/phone_numbers?filter[tag]=other'
    # Telnyx's active-call schema has leg IDs, but no from/to fields.
    reply(200, {'data': [{'call_control_id': c['call_control_id'], 'call_leg_id': c['call_leg_id']} for c in calls[:1]], 'meta': {'next': next_path}})

if method == 'GET' and path == '/v2/phone_numbers':
    numbers = read('telnyx-numbers.json')
    page = int(query.get('page[number]', ['1'])[0])
    reply(200, {'data': numbers[page - 1:page], 'meta': {'total_pages': len(numbers), 'page_number': page}})

if method == 'GET' and path == '/v2/call_events':
    if (api / 'telnyx-missing-events').exists():
        reply(200, {'data': [], 'meta': {'total_pages': 0}})
    calls = [c for c in read('telnyx.json') if c['call_leg_id'] == query['filter[leg_id]'][0]]
    for field in ('from', 'to'):
        if 'filter[' + field + ']' in query:
            calls = [c for c in calls if c[field] == query['filter[' + field + ']'][0]]
    reply(200, {'data': [{'call_leg_id': c['call_leg_id'], 'name': 'call.initiated'} for c in calls], 'meta': {'total_pages': 1}})

if method == 'GET' and path.endswith('/IncomingPhoneNumbers.json'):
    numbers = read('numbers.json')
    if 'PageToken' in query:
        numbers = numbers[1:]
    next_path = path + '?PageToken=next' if len(numbers) > 1 else None
    reply(200, {'incoming_phone_numbers': numbers[:1], 'next_page_uri': next_path})

if method == 'POST' and path.startswith('/v2/calls/'):
    call_id = path.split('/')[3]
    if (api / 'telnyx-hangup-error').exists() and call_id == 'v3:leg-a':
        reply(500, {'errors': [{'detail': 'KEYtestonly ' + call_id}]})
    calls = read('telnyx.json')
    for call in calls:
        if call['call_control_id'] == call_id:
            if not call['active']:
                reply(422, {'errors': [{'code': '90018', 'detail': 'already ended'}]})
            if not (api / 'telnyx-stubborn').exists():
                call['active'] = False
    if (api / 'telnyx-race').exists():
        for call in calls:
            call['active'] = False
    save('telnyx.json', calls)
    reply(200, {'data': {'result': 'ok'}})

if method == 'GET' and path.endswith('/Calls.json'):
    status = query['Status'][0]
    calls = [c for c in read('twilio.json') if c['status'] == status]
    if 'PageToken' in query:
        calls = [c for c in calls if c['sid'] > query['PageToken'][0]]
    next_path = None
    if len(calls) > 1:
        next_path = path + '?Status=' + status + '&PageToken=' + calls[0]['sid']
    if (api / 'twilio-bad-next').exists():
        next_path = '/2010-04-01/Accounts/ACother/Calls.json?Status=in-progress'
    if (api / 'twilio-missing-numbers').exists():
        calls = [{k: v for k, v in c.items() if k not in ('from', 'to')} for c in calls]
    reply(200, {'calls': calls[:1], 'next_page_uri': next_path})

if method == 'POST' and '/Calls/' in path:
    sid = path.split('/')[-1].removesuffix('.json')
    form = [args[i + 1] for i, arg in enumerate(args) if arg == '--data-urlencode']
    wanted = form[0].split('=', 1)[1]
    calls = read('twilio.json')
    for call in calls:
        if call['sid'] == sid:
            expected = 'completed' if call['status'] == 'in-progress' else 'canceled'
            assert wanted == expected, (sid, wanted, expected)
            call['status'] = wanted
    save('twilio.json', calls)
    reply(200, {'sid': sid, 'status': wanted})

reply(404, {'message': 'unexpected API request'})
FAKE
chmod +x "$scratch/bin/curl"

# Cleanup must work without provisioning or a reachable local/public endpoint.
cat > "$scratch/bin/tailscale" <<'FAKE'
#!/usr/bin/env bash
echo 'cleanup attempted to use Tailscale' >&2
exit 1
FAKE
chmod +x "$scratch/bin/tailscale"

export FAKE_API_DIR="$scratch/api"
export VXPIPE_LIVE_PROVIDERS_ENV_FILE="$scratch/credentials.env"
export VXPIPE_LIVETESTS_CURL_BIN="$scratch/bin/curl"
export VXPIPE_LIVETESTS_TAILSCALE_BIN="$scratch/bin/tailscale"
export VXPIPE_LIVETESTS_STATE_DIR="$scratch/state"
export VXP_TEST_MACHINE=rocksalt

credentials() {
  cat > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE" <<'ENV'
TELNYX_API_KEY=KEYtestonly
TWILIO_ACCOUNT_SID=ACtestonly
TWILIO_AUTH_TOKEN=twilio-token-test-only
ENV
}

reset_api() {
  rm -f "$scratch/api/"*-error "$scratch/api/"*-malformed "$scratch/api/"*-bad-next \
    "$scratch/api/"*-stubborn "$scratch/api/"*-race "$scratch/api/"*-missing-events "$scratch/api/"*-missing-numbers
  # The second application belongs to another machine: cleanup is account-wide.
  echo '[{"id":"app-a","application_name":"vxp-test-rocksalt"},{"id":"app-b","application_name":"other-machine"}]' > "$scratch/api/apps.json"
  cat > "$scratch/api/telnyx.json" <<'JSON'
[
  {"call_control_id":"v3:leg-a","call_leg_id":"leg-a","connection_id":"app-a","active":true,"from":"+13125550142","to":"+14155550199"},
  {"call_control_id":"v3:leg-b","call_leg_id":"leg-b","connection_id":"app-a","active":true,"from":"+14155550199","to":"+13125550142"},
  {"call_control_id":"v3:leg-c","call_leg_id":"leg-c","connection_id":"app-b","active":true,"from":"+13125550100","to":"+14155550100"},
  {"call_control_id":"v3:leg-d","call_leg_id":"leg-d","connection_id":"app-b","active":true,"from":"+14155550199","to":"+13125550143"},
  {"call_control_id":"v3:leg-e","call_leg_id":"leg-e","connection_id":"app-a","active":true,"from":"+13125550100","to":"+14155550100"},
  {"call_control_id":"v3:ended","call_leg_id":"ended","connection_id":"app-a","active":false,"from":"+13125550142","to":"+14155550199"}
]
JSON
  echo '[{"phone_number":"+13125550100","connection_id":"app-a","tags":["vxp-test-rocksalt-other"]},{"phone_number":"+13125550142","connection_id":"app-a","tags":["vxp-test-rocksalt"]},{"phone_number":"+13125550143","connection_id":"app-b","tags":["vxp-test-rocksalt-b"]}]' > "$scratch/api/telnyx-numbers.json"
  cat > "$scratch/api/twilio.json" <<'JSON'
[
  {"sid":"CAactive1","status":"in-progress","from":"+14155550199","to":"+13125550142"},
  {"sid":"CAactive2","status":"in-progress","from":"+13125550142","to":"+14155550199"},
  {"sid":"CAqueued","status":"queued","from":"+14155550199","to":"+13125550142"},
  {"sid":"CAringing","status":"ringing","from":"+13125550142","to":"+14155550199"},
  {"sid":"CAother","status":"in-progress","from":"+14155550100","to":"+13125550100"},
  {"sid":"CAended","status":"completed","from":"+14155550199","to":"+13125550142"}
]
JSON
  echo '[{"phone_number":"+14155550100","friendly_name":"vxp-test-rocksalt-other"},{"phone_number":"+14155550199","friendly_name":"vxp-test-rocksalt"}]' > "$scratch/api/numbers.json"
  : > "$scratch/api/log"
  credentials
}

livetests() { "$repo_root/bin/livetests" "$@" > "$scratch/out" 2> "$scratch/err"; }
telnyx_empty() { jq -e 'all(.[]; .active == false)' "$scratch/api/telnyx.json" > /dev/null; }
twilio_empty() { jq -e 'all(.[]; .status == "completed" or .status == "canceled")' "$scratch/api/twilio.json" > /dev/null; }

reset_api
livetests telephony:hangup --all-calls || fail 'account-wide cleanup failed'
telnyx_empty || fail 'Telnyx left active calls on a later call/application page'
twilio_empty || fail 'Twilio left active, ringing or queued calls'
rg -q 'telnyx.*no active calls' "$scratch/out" || fail 'Telnyx verification missing'
rg -q 'twilio.*no active calls' "$scratch/out" || fail 'Twilio verification missing'
rg -q 'v3:ended|CAended.json' "$scratch/api/log" && fail 'attempted to end an already completed call'
rg '^ARGV ' "$scratch/api/log" > "$scratch/argv"
rg -q 'KEYtestonly|twilio-token-test-only' "$scratch/argv" && fail 'credential sent through argv'
cat "$scratch/out" "$scratch/err" > "$scratch/reports"
rg -q 'KEYtestonly|twilio-token-test-only|ACtestonly|v3:leg' "$scratch/reports" && fail 'credential or call control token reported'

# Repeating cleanup is a verified, mutation-free success.
: > "$scratch/api/log"
livetests telephony:hangup --all-calls || fail 'repeated cleanup failed'
rg -q 'POST' "$scratch/api/log" && fail 'empty accounts caused a hangup request'

# Provider resource responses can exceed the OS argument-size limit. Large
# unused application metadata must never turn a populated account into "empty".
reset_api
jq 'map(. + {metadata: ("x" * 200000)})' "$scratch/api/apps.json" > "$scratch/apps"
mv "$scratch/apps" "$scratch/api/apps.json"
livetests telephony:hangup --all-calls || fail 'large application response broke cleanup'
telnyx_empty || fail 'large application metadata caused a false empty inventory'

for provider in telnyx twilio; do
  reset_api
  livetests "$provider:hangup" --all-calls || fail "$provider cleanup failed"
  other=telnyx
  [[ "$provider" == telnyx ]] && other=twilio
  rg -q "api.$other.com" "$scratch/api/log" && fail "$provider cleanup contacted $other"
done

# The default targets only this machine, in both call directions, without
# depending on the machine's current webhook wiring or Tailscale availability.
for command in telephony:hangup telnyx:hangup twilio:hangup; do
  reset_api
  livetests "$command" || fail "$command machine cleanup failed"
  if [[ "$command" != twilio:hangup ]]; then
    [[ "$(jq -r '[.[] | select(.active)] | map(.call_control_id) | join(",")' "$scratch/api/telnyx.json")" == 'v3:leg-c,v3:leg-e' ]] || fail 'default Telnyx cleanup touched other numbers or left this machine active'
  fi
  if [[ "$command" != telnyx:hangup ]]; then
    [[ "$(jq -r '[.[] | select(.status == "in-progress" or .status == "queued" or .status == "ringing")] | map(.sid) | join(",")' "$scratch/api/twilio.json")" == 'CAother' ]] || fail 'default Twilio cleanup touched another machine or left this machine active'
  fi
done

# Missing number evidence must fail closed instead of hanging up an entire app.
reset_api
touch "$scratch/api/telnyx-missing-events"
if livetests telnyx:hangup; then fail 'unclassified Telnyx calls reported success'; fi
rg -q 'POST' "$scratch/api/log" && fail 'Telnyx hung up calls without number evidence'

reset_api
touch "$scratch/api/twilio-missing-numbers"
if livetests twilio:hangup; then fail 'unclassified Twilio calls reported success'; fi
rg -q 'POST' "$scratch/api/log" && fail 'Twilio hung up calls without number evidence'

# No provisioned numbers means no eligible calls; unrelated call evidence need
# not be queried, and account calls must remain untouched.
reset_api
echo '[]' > "$scratch/api/telnyx-numbers.json"
echo '[]' > "$scratch/api/numbers.json"
touch "$scratch/api/telnyx-missing-events"
livetests telephony:hangup || fail 'cleanup without provisioned numbers failed'
rg -q '/active_calls|/call_events|/Calls.json|POST' "$scratch/api/log" && fail 'cleanup queried or mutated unrelated calls without test numbers'

# Tags must be arrays of exact tags, never a substring match on malformed data.
reset_api
echo '[{"phone_number":"+13125550100","tags":"vxp-test-rocksalt-other"}]' > "$scratch/api/telnyx-numbers.json"
if livetests telnyx:hangup; then fail 'malformed number tags reported success'; fi
rg -q 'POST' "$scratch/api/log" && fail 'malformed tags broadened cleanup scope'

# An unavailable account must not prevent the other provider from being cleaned.
reset_api
touch "$scratch/api/telnyx-list-error"
if livetests telephony:hangup --all-calls; then fail 'an unverified provider reported success'; fi
twilio_empty || fail 'Telnyx failure prevented Twilio cleanup'
rg -q 'HTTP 401' "$scratch/err" || fail 'HTTP failure not reported'
rg -q 'KEYtestonly|twilio-token-test-only|ACtestonly|v3:leg' "$scratch/err" && fail 'error response leaked secrets'

# Continue through per-call errors, but fail when the final inventory is nonempty.
reset_api
touch "$scratch/api/telnyx-hangup-error"
if livetests telephony:hangup --all-calls; then fail 'lingering call reported success'; fi
[[ "$(jq '[.[] | select(.active)] | length' "$scratch/api/telnyx.json")" == 1 ]] || fail 'a failed hangup prevented other Telnyx calls from ending'
twilio_empty || fail 'a failed hangup prevented Twilio cleanup'
rg -q 'active calls remain' "$scratch/err" || fail 'remaining calls not reported'
rg -q 'KEYtestonly|v3:leg' "$scratch/err" && fail 'hangup error leaked credentials'

# Paired call legs can disappear between enumeration and their hangup request.
reset_api
touch "$scratch/api/telnyx-race"
livetests telnyx:hangup --all-calls || fail 'already-ended paired leg failed verified cleanup'
telnyx_empty || fail 'paired call legs left active'

reset_api
touch "$scratch/api/telnyx-stubborn"
if livetests telnyx:hangup --all-calls; then fail 'accepted hangups with lingering calls reported success'; fi
rg -q 'active calls remain' "$scratch/err" || fail 'accepted-but-active calls not reported'

# A single configured provider works; ambient credentials must not be used.
reset_api
echo 'TWILIO_ACCOUNT_SID=ACtestonly' > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
echo 'TWILIO_AUTH_TOKEN=twilio-token-test-only' >> "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
export TELNYX_API_KEY=ambient-test-only
livetests telephony:hangup --all-calls || fail 'Twilio-only cleanup failed'
twilio_empty || fail 'Twilio-only cleanup left calls active'
rg -q 'api.telnyx.com' "$scratch/api/log" && fail 'ambient Telnyx credentials were used'
if livetests telnyx:hangup; then fail 'missing selected-provider credentials succeeded'; fi
rg -q 'TELNYX_API_KEY' "$scratch/err" || fail 'missing credential not named'

reset_api
echo 'TELNYX_API_KEY=KEYtestonly' > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
livetests telephony:hangup --all-calls || fail 'Telnyx-only cleanup failed'
telnyx_empty || fail 'Telnyx-only cleanup left calls active'

reset_api
echo 'TWILIO_ACCOUNT_SID=ACtestonly' > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
if livetests telephony:hangup; then fail 'partial credentials reported success'; fi
rg -q 'TWILIO_AUTH_TOKEN' "$scratch/err" || fail 'incomplete Twilio configuration not explained'

reset_api
: > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
if livetests telephony:hangup; then fail 'no configured providers reported success'; fi

for provider in telnyx twilio; do
  for fault in malformed bad-next transport-error; do
    reset_api
    touch "$scratch/api/$provider-$fault"
    if livetests "$provider:hangup" --all-calls; then fail "$provider $fault reported success"; fi
    rg -q 'POST' "$scratch/api/log" && fail "$provider mutated calls after invalid enumeration"
  done
done

# Reject ignored arguments before loading credentials or touching either account.
reset_api
if livetests telephony:hangup unexpected; then fail 'unexpected argument was ignored'; fi
[[ ! -s "$scratch/api/log" ]] || fail 'invalid arguments contacted a provider'

livetests help
for command in telephony:hangup telnyx:hangup twilio:hangup; do
  rg -q -F "$command" "$scratch/out" || fail "$command not documented in help"
done

printf 'livetests hangup checks passed\n'
