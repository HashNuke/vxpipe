#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d -t vxpipe-livetests-telephony.XXXXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$scratch/bin" "$scratch/api/telnyx" "$scratch/api/twilio"

# Fake curl backed by JSON state files for the Telnyx v2 and Twilio REST APIs
# that provisioning uses. Every call is logged with its argv and its stdin config.
cat > "$scratch/bin/curl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
api="$FAKE_API_DIR"
method=GET body="" form=() url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -w|-H) shift 2 ;;
    -K) shift 2 ;;
    --data) body="$2"; shift 2 ;;
    --data-urlencode) form+=("$2"); shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
config="$(cat)"
printf 'ARGV %s %s %s %s\n' "$method" "$url" "$body" "${form[*]:-}" >> "$api/log"
printf 'CONFIG %s\n' "$config" >> "$api/log"

reply() { printf '%s\n%s' "$2" "$1"; exit 0; }
query() { sed -n "s/.*[?&]$1=\\([^&]*\\).*/\\1/p" <<< "$url" | sed 's/%2B/+/g'; }
next_id() { local n; n="$(cat "$api/next" 2>/dev/null || echo 100)"; echo $((n + 1)) > "$api/next"; echo "$n"; }
field() { local f; for f in "${form[@]}"; do [[ "$f" == "$1="* ]] && printf '%s' "${f#*=}"; done; }

path="${url#https://api.telnyx.com/v2}"
if [[ "$path" != "$url" ]]; then
  grep -q 'Authorization: Bearer ' <<< "$config" || reply 401 '{"errors":[{"detail":"no auth"}]}'
  path="${path%%\?*}"
  case "$method $path" in
    "GET /outbound_voice_profiles")
      name="$(query 'filter\[name\]\[contains\]')"
      reply 200 "$(jq -c --arg n "$name" '{data: [.[] | select(.name | contains($n))]}' "$api/telnyx/profiles.json")" ;;
    "POST /outbound_voice_profiles")
      id="$(next_id)"
      jq --argjson b "$body" --arg id "$id" '. + [$b + {id: $id}]' "$api/telnyx/profiles.json" > "$api/t" && mv "$api/t" "$api/telnyx/profiles.json"
      reply 201 "$(jq -c --argjson b "$body" --arg id "$id" '{data: ($b + {id: $id})}' <<< null)" ;;
    "GET /call_control_applications")
      name="$(query 'filter\[application_name\]\[contains\]')"
      reply 200 "$(jq -c --arg n "$name" '{data: [.[] | select(.application_name | contains($n))]}' "$api/telnyx/apps.json")" ;;
    "POST /call_control_applications")
      id="$(next_id)"
      jq --argjson b "$body" --arg id "$id" '. + [$b + {id: $id}]' "$api/telnyx/apps.json" > "$api/t" && mv "$api/t" "$api/telnyx/apps.json"
      reply 201 "$(jq -c --argjson b "$body" --arg id "$id" '{data: ($b + {id: $id})}' <<< null)" ;;
    "PATCH /call_control_applications/"*)
      id="${path##*/}"
      jq --argjson b "$body" --arg id "$id" 'map(if .id == $id then . * $b else . end)' "$api/telnyx/apps.json" > "$api/t" && mv "$api/t" "$api/telnyx/apps.json"
      reply 200 "$(jq -c --arg id "$id" '{data: (.[] | select(.id == $id))}' "$api/telnyx/apps.json")" ;;
    "GET /phone_numbers")
      tag="$(query 'filter\[tag\]')"; number="$(query 'filter\[phone_number\]')"
      reply 200 "$(jq -c --arg t "$tag" --arg p "$number" '{data: [.[] | select(($t == "" or ((.tags // []) | index($t))) and ($p == "" or .phone_number == $p))]}' "$api/telnyx/numbers.json")" ;;
    "PATCH /phone_numbers/"*)
      id="${path##*/}"
      jq --argjson b "$body" --arg id "$id" 'map(if .id == $id then . + $b else . end)' "$api/telnyx/numbers.json" > "$api/t" && mv "$api/t" "$api/telnyx/numbers.json"
      reply 200 "$(jq -c --arg id "$id" '{data: (.[] | select(.id == $id))}' "$api/telnyx/numbers.json")" ;;
    "GET /available_phone_numbers")
      reply 200 "$(jq -c --slurpfile owned "$api/telnyx/numbers.json" '{data: [map(select(. as $p | ($owned[0] | map(.phone_number) | index($p)) | not))[0:1][] | {phone_number: .}]}' "$api/telnyx/available.json")" ;;
    "POST /number_orders")
      [[ -f "$api/telnyx/order_error" ]] && reply 422 "$(cat "$api/telnyx/order_error")"
      number="$(jq -r '.phone_numbers[0].phone_number' <<< "$body")"
      connection="$(jq -r '.connection_id' <<< "$body")"
      id="$(next_id)"
      jq --arg p "$number" --arg c "$connection" --arg id "$id" '. + [{id: $id, phone_number: $p, connection_id: $c, tags: []}]' "$api/telnyx/numbers.json" > "$api/t" && mv "$api/t" "$api/telnyx/numbers.json"
      reply 200 '{"data":{"status":"success"}}' ;;
  esac
  reply 404 "{\"errors\":[{\"detail\":\"unexpected $method $path\"}]}"
fi

path="${url#https://api.twilio.com/2010-04-01/Accounts/}"
if [[ "$path" != "$url" ]]; then
  grep -q '^user = "AC' <<< "$config" || reply 401 '{"message":"no auth"}'
  [[ -f "$api/twilio/inactive" ]] && reply 401 '{"message":"authentication failed, account ACtestonly with status 4 is not active"}'
  path="/${path#*/}"
  path="${path%%\?*}"
  case "$method $path" in
    "GET /IncomingPhoneNumbers.json")
      name="$(query FriendlyName)"
      reply 200 "$(jq -c --arg n "$name" '{incoming_phone_numbers: [.[] | select(.friendly_name == $n)]}' "$api/twilio/numbers.json")" ;;
    "POST /IncomingPhoneNumbers.json")
      [[ -f "$api/twilio/purchase_error" ]] && reply 401 "$(cat "$api/twilio/purchase_error")"
      sid="PN$(next_id)"
      jq --arg s "$sid" --arg p "$(field PhoneNumber)" --arg f "$(field FriendlyName)" --arg v "$(field VoiceUrl)" --arg m "$(field VoiceMethod)" \
        '. + [{sid: $s, phone_number: $p, friendly_name: $f, voice_url: $v, voice_method: $m}]' "$api/twilio/numbers.json" > "$api/t" && mv "$api/t" "$api/twilio/numbers.json"
      reply 201 "$(jq -c --arg s "$sid" '.[] | select(.sid == $s)' "$api/twilio/numbers.json")" ;;
    "POST /IncomingPhoneNumbers/"*)
      sid="${path##*/}"; sid="${sid%.json}"
      jq --arg s "$sid" --arg v "$(field VoiceUrl)" --arg m "$(field VoiceMethod)" \
        'map(if .sid == $s then . + {voice_url: $v, voice_method: $m} else . end)' "$api/twilio/numbers.json" > "$api/t" && mv "$api/t" "$api/twilio/numbers.json"
      reply 200 "$(jq -c --arg s "$sid" '.[] | select(.sid == $s)' "$api/twilio/numbers.json")" ;;
    "GET /AvailablePhoneNumbers/US/Local.json")
      reply 200 "$(jq -c '{available_phone_numbers: [.[0:1][] | {phone_number: .}]}' "$api/twilio/available.json")" ;;
  esac
  reply 404 "{\"message\":\"unexpected $method $path\"}"
fi
echo "unexpected url $url" >&2
exit 7
FAKE

# Fake tailscale: the host node supplies the tailnet DNS suffix.
cat > "$scratch/bin/tailscale" <<'FAKE'
#!/usr/bin/env bash
[[ "$*" == "status --json" ]] && { echo '{"MagicDNSSuffix":"tail0000.ts.net"}'; exit 0; }
echo "unexpected tailscale call: $*" >&2
exit 1
FAKE

cat > "$scratch/bin/mix" <<'MIX'
#!/usr/bin/env bash
env | grep -E '^(TELNYX_APP_ID|TELNYX_TEST_FROM|TELNYX_TEST_TO|TELNYX_TEST_DESTINATION|TWILIO_TEST_FROM|TWILIO_TEST_DESTINATION)=' | sort > "$VXPIPE_LIVE_RUNNER_TEST_OUTPUT"
MIX
chmod +x "$scratch/bin/"*

reset_api() {
  echo '[]' > "$scratch/api/telnyx/profiles.json"
  echo '[]' > "$scratch/api/telnyx/apps.json"
  # Another machine's resources must never be touched or adopted.
  echo '[{"id":"9","phone_number":"+13125550100","tags":["vxp-test-wheeljack"],"connection_id":"wheeljack-app"}]' \
    > "$scratch/api/telnyx/numbers.json"
  echo '["+13125550142","+13125550143"]' > "$scratch/api/telnyx/available.json"
  rm -f "$scratch/api/telnyx/order_error" "$scratch/api/twilio/inactive"
  echo '[{"sid":"PN9","phone_number":"+14155550100","friendly_name":"vxp-test-wheeljack","voice_url":"https://wheeljack/voice","voice_method":"POST"}]' \
    > "$scratch/api/twilio/numbers.json"
  echo '["+14155550199"]' > "$scratch/api/twilio/available.json"
  : > "$scratch/api/log"
}

export FAKE_API_DIR="$scratch/api"
export VXPIPE_LIVETESTS_CURL_BIN="$scratch/bin/curl"
export VXPIPE_LIVETESTS_TAILSCALE_BIN="$scratch/bin/tailscale"
export VXPIPE_LIVE_PROVIDERS_MIX_BIN="$scratch/bin/mix"
export VXPIPE_LIVE_RUNNER_TEST_OUTPUT="$scratch/output"
export VXPIPE_LIVE_PROVIDERS_ENV_FILE="$scratch/live_providers.env"
export VXPIPE_LIVETESTS_STATE_DIR="$scratch/state"
export VXP_TEST_MACHINE=rocksalt
cat > "$VXPIPE_LIVE_PROVIDERS_ENV_FILE" <<'ENV'
TELNYX_API_KEY=KEYtestonly
TWILIO_ACCOUNT_SID=ACtestonly
TWILIO_AUTH_TOKEN=twilio-token-test-only
ENV

livetests() { "$repo_root/bin/livetests" "$@"; }
log_has() { rg -q -F -- "$1" "$scratch/api/log"; }
url="https://vxp-test-rocksalt.tail0000.ts.net"

# A Telnyx API error stops provisioning with a failure instead of reporting success.
reset_api
echo '{"errors":[{"detail":"Number is no longer available."}]}' > "$scratch/api/telnyx/order_error"
if livetests telephony:provision --allow-purchase > "$scratch/out" 2> "$scratch/err"; then
  fail "provision reported success after a Telnyx error"
fi
rg -q -F 'no longer available' "$scratch/err" || fail "Telnyx error not shown"
rg -q -F 'ready' "$scratch/out" && fail "provision printed ready after a Telnyx error"

# Twilio is optional: its errors are reported, Telnyx is still provisioned, and no secret leaks.
reset_api
echo '{"message":"Primary compliance profile is not approved."}' > "$scratch/api/twilio/purchase_error"
livetests telephony:provision --allow-purchase > "$scratch/out" 2> "$scratch/err" ||
  fail "a Twilio error stopped Telnyx provisioning"
rg -q -F 'compliance profile' "$scratch/err" || fail "Twilio error not shown"
rg -q -F 'twilio unavailable' "$scratch/out" || fail "unavailable Twilio not reported"
rg -q -F 'ACtestonly' "$scratch/err" && fail "account SID printed in an error"
rm "$scratch/api/twilio/purchase_error"

# Without --allow-purchase nothing is bought and the missing numbers are named.
reset_api
if livetests telephony:provision > "$scratch/out" 2> "$scratch/err"; then
  fail "provision without numbers succeeded"
fi
log_has 'POST https://api.telnyx.com/v2/number_orders' && fail "bought a Telnyx number without --allow-purchase"
log_has 'POST https://api.twilio.com/2010-04-01/Accounts/ACtestonly/IncomingPhoneNumbers.json' \
  && fail "bought a Twilio number without --allow-purchase"
rg -q -F -- '--allow-purchase' "$scratch/err" || fail "missing purchase flag not explained"

# With --allow-purchase every missing resource is created and wired.
reset_api
livetests telephony:provision --allow-purchase > "$scratch/out"
profile_id="$(jq -r '.[] | select(.name == "vxp-test-rocksalt") | .id' "$scratch/api/telnyx/profiles.json")"
[[ -n "$profile_id" ]] || fail "outbound profile not created"
[[ "$(jq -c '.[] | select(.name == "vxp-test-rocksalt") | .whitelisted_destinations' "$scratch/api/telnyx/profiles.json")" == '["US"]' ]] \
  || fail "outbound profile does not allow US"
app="$(jq -c '.[] | select(.application_name == "vxp-test-rocksalt")' "$scratch/api/telnyx/apps.json")"
[[ "$(jq -r '.webhook_event_url' <<< "$app")" == "$url/webhooks/platform/telnyx" ]] || fail "app webhook wrong: $app"
[[ "$(jq -r '.outbound.outbound_voice_profile_id' <<< "$app")" == "$profile_id" ]] || fail "profile not attached"
app_id="$(jq -r '.id' <<< "$app")"
number="$(jq -c '.[] | select(.phone_number == "+13125550142")' "$scratch/api/telnyx/numbers.json")"
[[ "$(jq -r '.connection_id' <<< "$number")" == "$app_id" ]] || fail "Telnyx number not assigned to the app"
[[ "$(jq -r '.tags | index("vxp-test-rocksalt")' <<< "$number")" != null ]] || fail "Telnyx number not tagged"
# A second Telnyx number receives the Telnyx-to-Telnyx calls.
second="$(jq -c '.[] | select(.phone_number == "+13125550143")' "$scratch/api/telnyx/numbers.json")"
[[ "$(jq -r '.connection_id' <<< "$second")" == "$app_id" ]] || fail "second Telnyx number not assigned to the app"
[[ "$(jq -c '.tags' <<< "$second")" == '["vxp-test-rocksalt-b"]' ]] || fail "second Telnyx number not tagged: $second"
rg -q -F '+13125550143' "$scratch/out" || fail "second Telnyx number not reported"
twilio="$(jq -c '.[] | select(.friendly_name == "vxp-test-rocksalt")' "$scratch/api/twilio/numbers.json")"
[[ "$(jq -r '.phone_number' <<< "$twilio")" == "+14155550199" ]] || fail "Twilio number not bought"
[[ "$(jq -r '.voice_url' <<< "$twilio")" == "$url/api/telephony/twilio/vxp-test-twilio/voice" ]] || fail "Twilio voice URL wrong"
rg -q -F '+13125550142' "$scratch/out" || fail "Telnyx number not reported"
rg -q -F '+14155550199' "$scratch/out" || fail "Twilio number not reported"

# Secrets travel only in curl's stdin config, never argv.
rg -q -F 'twilio-token-test-only' <(grep '^ARGV' "$scratch/api/log") && fail "Twilio token in argv"
rg -q -F 'KEYtestonly' <(grep '^ARGV' "$scratch/api/log") && fail "Telnyx key in argv"

# A second run finds everything and changes nothing.
: > "$scratch/api/log"
livetests telephony:provision --allow-purchase > "$scratch/out" 2>&1
grep '^ARGV' "$scratch/api/log" | grep -qvE '^ARGV GET ' && fail "second provision run changed something"
rg -q found "$scratch/out" || fail "second run did not report found resources"

# Drifted settings are repaired in place.
jq 'map(.webhook_event_url = "https://old.example/hook")' "$scratch/api/telnyx/apps.json" > "$scratch/t" && mv "$scratch/t" "$scratch/api/telnyx/apps.json"
jq 'map(if .friendly_name == "vxp-test-rocksalt" then .voice_url = "https://old.example/voice" else . end)' "$scratch/api/twilio/numbers.json" > "$scratch/t" && mv "$scratch/t" "$scratch/api/twilio/numbers.json"
livetests telephony:provision > /dev/null
[[ "$(jq -r '.[] | select(.application_name == "vxp-test-rocksalt") | .webhook_event_url' "$scratch/api/telnyx/apps.json")" == "$url/webhooks/platform/telnyx" ]] \
  || fail "app webhook not repaired"
[[ "$(jq -r '.[] | select(.friendly_name == "vxp-test-rocksalt") | .voice_url' "$scratch/api/twilio/numbers.json")" == "$url/api/telephony/twilio/vxp-test-twilio/voice" ]] \
  || fail "Twilio voice URL not repaired"

# The other machine's resources were never modified.
[[ "$(jq -r '.[] | select(.id == "9") | .connection_id' "$scratch/api/telnyx/numbers.json")" == wheeljack-app ]] || fail "touched wheeljack's Telnyx number"
[[ "$(jq -r '.[] | select(.sid == "PN9") | .voice_url' "$scratch/api/twilio/numbers.json")" == https://wheeljack/voice ]] || fail "touched wheeljack's Twilio number"

# telephony:status is read-only and reports what exists.
: > "$scratch/api/log"
livetests telephony:status > "$scratch/out"
grep '^ARGV' "$scratch/api/log" | grep -qvE '^ARGV GET ' && fail "telephony:status changed something"
rg -q -F '+13125550142' "$scratch/out" || fail "status missing Telnyx number"
rg -q -F "$app_id" "$scratch/out" || fail "status missing Telnyx app"

# Telephony runs export the discovered resources; each number calls the other.
printf 'TELEPHONY_TEST_PUBLIC_URL=%s\n' "$url" >> "$VXPIPE_LIVE_PROVIDERS_ENV_FILE"
: > "$scratch/api/log"
livetests run --only live_twilio apps/vxpipe_gateway/test/integration
grep '^ARGV' "$scratch/api/log" | grep -qvE '^ARGV GET ' && fail "run changed carrier state"
diff <(cat "$scratch/output") <(sort <<EOF
TELNYX_APP_ID=$app_id
TELNYX_TEST_FROM=+13125550142
TELNYX_TEST_TO=+13125550143
TELNYX_TEST_DESTINATION=+13125550143
TWILIO_TEST_FROM=+14155550199
TWILIO_TEST_DESTINATION=+13125550142
EOF
) || fail "discovered resources not exported"

# With Twilio unusable, telephony runs on Telnyx alone; an explicit Twilio selection fails.
touch "$scratch/api/twilio/inactive"
livetests run --only live_telephony apps/vxpipe_console/test/integration 2> "$scratch/err" ||
  fail "an inactive Twilio account stopped a Telnyx telephony run"
diff <(cat "$scratch/output") <(sort <<EOF
TELNYX_APP_ID=$app_id
TELNYX_TEST_FROM=+13125550142
TELNYX_TEST_TO=+13125550143
TELNYX_TEST_DESTINATION=+13125550143
EOF
) || fail "Telnyx-only resources not exported"
rg -q -F 'Twilio' "$scratch/err" || fail "unavailable Twilio not reported"
rg -q -F 'ACtestonly' "$scratch/err" && fail "account SID printed from a Twilio error"
rm -f "$scratch/output"
if livetests run --only live_twilio apps/vxpipe_gateway/test/integration 2> "$scratch/err"; then
  fail "a Twilio selection ran without Twilio"
fi
[[ ! -e "$scratch/output" ]] || fail "Twilio tests started without Twilio"
rm "$scratch/api/twilio/inactive"

# A run against an unprovisioned account names the fix and does not start tests.
reset_api
rm -f "$scratch/output"
if livetests run --only live_telnyx apps/vxpipe_gateway/test/integration 2> "$scratch/err"; then
  fail "run without provisioned resources succeeded"
fi
rg -q -F 'telephony:provision' "$scratch/err" || fail "missing provisioning not explained"
[[ ! -e "$scratch/output" ]] || fail "tests started without provisioned resources"

printf 'livetests telephony checks passed\n'
