# Sourced by bin/livetests only for explicit call cleanup commands.

cleanup_error() {
  printf 'livetests: %s\n' "$*" >&2
  return 1
}

# Bound requests and omit provider response text/URLs from errors: Telnyx call
# control IDs are tokens, and carrier error bodies can echo credentials or PII.
cleanup_request() {
  local provider="$1" method="$2" path="$3" config url response status
  shift 3
  if [[ "$provider" == telnyx ]]; then
    config="header = \"Authorization: Bearer $TELNYX_API_KEY\""
    url="https://api.telnyx.com/v2$path"
  else
    config="user = \"$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN\""
    url="https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID$path"
  fi
  response="$(printf '%s\n' "$config" |
    "$curl_bin" -sS -g -K - --connect-timeout 10 --max-time 30 \
      -X "$method" -w $'\n%{http_code}' "$@" "$url" 2>/dev/null)" || {
    cleanup_error "$provider cleanup $method request failed (transport error or timeout)"
    return 1
  }
  status="${response##*$'\n'}"
  [[ "$status" =~ ^2[0-9][0-9]$ ]] || {
    cleanup_error "$provider cleanup $method request returned HTTP $status"
    return 1
  }
  printf '%s' "${response%$'\n'*}"
}

cleanup_json() {
  local provider="$1" body="$2" filter="$3"
  shift 3
  jq -cer "$@" "$filter" <<< "$body" 2>/dev/null ||
    cleanup_error "$provider cleanup received an invalid response"
}

# Stream accumulated JSON through stdin instead of passing carrier payloads as
# argv. OS argument limits must not truncate discovery or hide a merge failure.
cleanup_append() {
  local provider="$1"
  printf '%s\n%s\n' "$2" "$3" | jq -ces 'add' 2>/dev/null ||
    cleanup_error "$provider cleanup could not combine inventory pages"
}

# Discover independently of provisioning: cleanup still works with stale
# webhooks, absent profiles or an unavailable public endpoint.
cleanup_telnyx_applications() {
  local page=1 total response chunk applications='[]'
  while :; do
    response="$(cleanup_request telnyx GET "/call_control_applications?page[number]=$page&page[size]=250")" || return 1
    chunk="$(cleanup_json telnyx "$response" '
      if (.data | type) == "array" and all(.data[]; (.id | type) == "string" and (.id | length) > 0)
      then [.data[] | {id: .id}] else error("applications") end')" || return 1
    applications="$(cleanup_append telnyx "$applications" "$chunk")" || return 1
    total="$(cleanup_json telnyx "$response" '
      .meta.total_pages | if type == "number" and . >= 0 and floor == . then . else error("pages") end')" || return 1
    (( page >= total )) && break
    ((page += 1))
  done
  jq -c 'unique_by(.id)' <<< "$applications"
}

cleanup_telnyx_numbers() {
  local page=1 total response chunk numbers='[]'
  while :; do
    response="$(cleanup_request telnyx GET "/phone_numbers?page[number]=$page&page[size]=250")" || return 1
    chunk="$(cleanup_json telnyx "$response" '
      if (.data | type) == "array" and all(.data[];
        (.tags // [] | type) == "array" and all((.tags // [])[]; type == "string"))
      then [.data[] | select((.tags // [] | index($machine)) != null or (.tags // [] | index($machine + "-b")) != null)]
        | if all(.[]; (.phone_number | type) == "string" and (.phone_number | length) > 0)
          then . else error("numbers") end
      else error("numbers") end' --arg machine "$node_name")" || return 1
    numbers="$(cleanup_append telnyx "$numbers" "$chunk")" || return 1
    total="$(cleanup_json telnyx "$response" '
      .meta.total_pages | if type == "number" and . >= 0 and floor == . then . else error("pages") end')" || return 1
    (( page >= total )) && break
    ((page += 1))
  done
  jq -c '[.[].phone_number] | unique' <<< "$numbers"
}

# The active-call and call-status APIs do not expose numbers. Use the documented
# call-events from/to filters for the exact live leg, and require an initiated
# event before classifying it. Missing evidence never widens cleanup to an app.
cleanup_telnyx_event_count() {
  local leg="$1" field="${2:-}" number="${3:-}" response path
  path="/call_events?filter[leg_id]=$(jq -rn --arg leg "$leg" '$leg | @uri')&filter[type]=webhook&filter[name]=call.initiated&page[size]=1"
  [[ -z "$field" ]] || path+="&filter[$field]=$(jq -rn --arg number "$number" '$number | @uri')"
  response="$(cleanup_request telnyx GET "$path")" || return 1
  cleanup_json telnyx "$response" '
    if (.data | type) == "array" and all(.data[]; .call_leg_id == $leg and .name == "call.initiated")
    then .data | length else error("events") end' --arg leg "$leg"
}

cleanup_telnyx_matches_number() {
  local leg="$1" numbers="$2" count number field values
  count="$(cleanup_telnyx_event_count "$leg")" || return 1
  [[ "$count" -gt 0 ]] || { cleanup_error 'telnyx cleanup cannot establish call numbers: initiated event unavailable'; return 1; }
  values="$(jq -r '.[]' <<< "$numbers")"
  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    for field in from to; do
      count="$(cleanup_telnyx_event_count "$leg" "$field" "$number")" || return 1
      if [[ "$count" -gt 0 ]]; then
        printf true
        return 0
      fi
    done
  done <<< "$values"
  printf false
}

cleanup_twilio_page() {
  local path="$1" response next prefix="/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID"
  response="$(cleanup_request twilio GET "$path")" || return 1
  next="$(cleanup_json twilio "$response" '
    .next_page_uri | if . == null then "" elif type == "string" then . else error("next page") end')" || return 1
  if [[ -n "$next" ]]; then
    [[ "$next" == "$prefix${path%%\?*}?"* ]] || {
      cleanup_error 'twilio cleanup received an unexpected pagination path'
      return 1
    }
  fi
  printf '%s' "$response"
}

cleanup_twilio_numbers() {
  local path="/IncomingPhoneNumbers.json?FriendlyName=$node_name&PageSize=1000" response chunk next numbers='[]'
  local prefix="/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID" visited=''
  while [[ -n "$path" ]]; do
    [[ "$visited" != *"|$path|"* ]] || { cleanup_error 'twilio cleanup pagination repeated'; return 1; }
    visited+="|$path|"
    response="$(cleanup_twilio_page "$path")" || return 1
    chunk="$(cleanup_json twilio "$response" '
      if (.incoming_phone_numbers | type) == "array"
      then [.incoming_phone_numbers[] | select(.friendly_name == $machine) | .phone_number]
        | if all(.[]; type == "string" and length > 0) then . else error("numbers") end
      else error("numbers") end' --arg machine "$node_name")" || return 1
    numbers="$(cleanup_append twilio "$numbers" "$chunk")" || return 1
    next="$(jq -r '.next_page_uri // ""' <<< "$response")"
    path="${next#"$prefix"}"
  done
  printf '%s' "$numbers"
}

# Collect the complete inventory before ending anything, since mutations can
# shrink subsequent pages. Each inventory is reused only for one cleanup pass.
cleanup_telnyx_inventory() {
  local applications="$1" scope="$2" numbers="$3" app base path response chunk next calls='[]' visited
  local ids
  ids="$(jq -r '.[].id | @uri' <<< "$applications")"
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    base="/connections/$app/active_calls"
    path="$base?page[limit]=250"
    visited=''
    while [[ -n "$path" ]]; do
      [[ "$visited" != *"|$path|"* ]] || { cleanup_error 'telnyx cleanup pagination repeated'; return 1; }
      visited+="|$path|"
      response="$(cleanup_request telnyx GET "$path")" || return 1
      chunk="$(cleanup_json telnyx "$response" '
        if (.data | type) == "array" and all(.data[]; (.call_control_id | type) == "string" and (.call_control_id | length) > 0 and
          (.call_leg_id | type) == "string" and (.call_leg_id | length) > 0)
        then [.data[] | {id: .call_control_id, leg: .call_leg_id}] else error("calls") end')" || return 1
      calls="$(cleanup_append telnyx "$calls" "$chunk")" || return 1
      next="$(cleanup_json telnyx "$response" '
        .meta.next | if . == null then "" elif type == "string" then . else error("next page") end')" || return 1
      if [[ -n "$next" ]]; then
        [[ "$next" == "/v2$base?"* ]] || { cleanup_error 'telnyx cleanup received an unexpected pagination path'; return 1; }
      fi
      path="${next#/v2}"
    done
  done <<< "$ids"
  calls="$(jq -c 'unique_by(.id)' <<< "$calls")"
  if [[ "$scope" == machine ]]; then
    local row matches selected='[]' rows
    rows="$(jq -c '.[]' <<< "$calls")"
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      matches="$(cleanup_telnyx_matches_number "$(jq -r .leg <<< "$row")" "$numbers")" || return 1
      if [[ "$matches" == true ]]; then
        selected="$(cleanup_append telnyx "$selected" "[$row]")" || return 1
      fi
    done <<< "$rows"
    calls="$selected"
  fi
  printf '%s' "$calls"
}

cleanup_twilio_inventory() {
  local scope="$1" numbers="$2" status path response chunk next calls='[]' visited
  local prefix="/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID"
  for status in queued ringing in-progress; do
    path="/Calls.json?Status=$status&PageSize=1000"
    visited=''
    while [[ -n "$path" ]]; do
      [[ "$visited" != *"|$path|"* ]] || { cleanup_error 'twilio cleanup pagination repeated'; return 1; }
      visited+="|$path|"
      response="$(cleanup_twilio_page "$path")" || return 1
      chunk="$(cleanup_json twilio "$response" '
        if (.calls | type) == "array" and all(.calls[]; (.sid | type) == "string" and (.sid | length) > 0 and
          (.status == "queued" or .status == "ringing" or .status == "in-progress") and
          ($scope == "all" or ((.from | type) == "string" and (.to | type) == "string")))
        then [.calls[] | select($scope == "all" or (.from as $from | $numbers | index($from)) != null or
          (.to as $to | $numbers | index($to)) != null) | {id: .sid, status: .status}]
        else error("calls") end' --arg scope "$scope" --argjson numbers "$numbers")" || return 1
      calls="$(cleanup_append twilio "$calls" "$chunk")" || return 1
      next="$(jq -r '.next_page_uri // ""' <<< "$response")"
      path="${next#"$prefix"}"
    done
  done
  jq -c 'unique_by(.id)' <<< "$calls"
}

cleanup_provider() {
  local provider="$1" scope="$2" resources calls rows id status wanted pass count numbers='[]'
  if [[ "$provider" == telnyx ]]; then
    [[ -n "${TELNYX_API_KEY:-}" ]] || { cleanup_error 'set TELNYX_API_KEY for Telnyx cleanup'; return 1; }
    if [[ "$scope" == machine ]]; then
      numbers="$(cleanup_telnyx_numbers)" || return 1
      if [[ "$numbers" == '[]' ]]; then
        printf 'telnyx: no active calls (machine scope; no provisioned numbers)\n'
        return 0
      fi
    fi
    # A provisioned outbound number can be used on another application, so
    # enumerate every Call Control app and match the numbers on each live leg.
    resources="$(cleanup_telnyx_applications)" || return 1
  else
    twilio_credentials_present || { cleanup_error 'set TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN for Twilio cleanup'; return 1; }
    resources='[]'
    if [[ "$scope" == machine ]]; then
      resources="$(cleanup_twilio_numbers)" || return 1
      if [[ "$resources" == '[]' ]]; then
        printf 'twilio: no active calls (machine scope; no provisioned numbers)\n'
        return 0
      fi
    fi
  fi

  # Three attempts cover disappearing paired legs and calls answering while a
  # cancellation is in flight. The final read, not POST acceptance, proves exit.
  for pass in 1 2 3 4; do
    if [[ "$provider" == telnyx ]]; then
      calls="$(cleanup_telnyx_inventory "$resources" "$scope" "$numbers")" || return 1
    else
      calls="$(cleanup_twilio_inventory "$scope" "$resources")" || return 1
    fi
    count="$(jq 'length' <<< "$calls")"
    if [[ "$count" -eq 0 ]]; then
      printf '%s: no active calls (%s scope)\n' "$provider" "$scope"
      return 0
    fi
    [[ "$pass" -lt 4 ]] || { cleanup_error "$provider: $count active calls remain ($scope scope)"; return 1; }
    printf '%s: ending %s calls (%s scope, attempt %s/3)\n' "$provider" "$count" "$scope" "$pass" >&3
    rows="$(jq -r '.[] | [(.id | @uri), (.status // "")] | @tsv' <<< "$calls")"
    while IFS=$'\t' read -r id status; do
      if [[ "$provider" == telnyx ]]; then
        cleanup_request telnyx POST "/calls/$id/actions/hangup" \
          -H 'Content-Type: application/json' --data '{}' > /dev/null || true
      else
        wanted=canceled
        [[ "$status" == in-progress ]] && wanted=completed
        cleanup_request twilio POST "/Calls/$id.json" --data-urlencode "Status=$wanted" > /dev/null || true
      fi
    done <<< "$rows"
  done
}

hangup_calls() {
  local selection="$1" scope=machine failed=0 configured=0 provider
  shift
  case "$*" in
    '') ;;
    --all-calls) [[ $# -eq 1 ]] || die 'cleanup accepts only --all-calls'; scope=all ;;
    *) die 'cleanup accepts only --all-calls' ;;
  esac
  load_credentials
  for provider in telnyx twilio; do
    if [[ "$selection" == telephony ]]; then
      if [[ "$provider" == telnyx && -z "${TELNYX_API_KEY:-}" ]]; then
        printf 'telnyx: skipped (not configured)\n'
        continue
      elif [[ "$provider" == twilio && -z "${TWILIO_ACCOUNT_SID:-}" && -z "${TWILIO_AUTH_TOKEN:-}" ]]; then
        printf 'twilio: skipped (not configured)\n'
        continue
      fi
    elif [[ "$selection" != "$provider" ]]; then
      continue
    fi
    ((configured += 1))
    cleanup_provider "$provider" "$scope" || failed=1
  done
  [[ "$configured" -gt 0 ]] || die 'no telephony providers configured for cleanup'
  return "$failed"
}
