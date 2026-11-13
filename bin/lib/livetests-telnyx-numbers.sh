# Telnyx tags group reusable numbers; caller/receiver roles belong to local state.

telnyx_number_inventory() {
  local page=1 total response numbers='[]'
  while :; do
    response="$(telnyx_api GET "/phone_numbers?page[number]=$page&page[size]=250")" || return 2
    total="$(jq -er '.meta.total_pages | select(type == "number" and . >= 0 and floor == .)' <<< "$response")" || return 2
    numbers="$(printf '%s\n%s\n' "$numbers" "$response" | jq -ces '
      if (.[1].data | type) == "array" then .[0] + .[1].data else error("invalid number inventory") end')" || return 2
    (( page >= total )) && break
    ((page += 1))
  done
  jq -c 'unique_by(.id)' <<< "$numbers"
}

buy_telnyx_number() {
  local app_id="$1" candidate number attempt
  candidate="$(telnyx_api GET "/available_phone_numbers?filter[country_code]=US&filter[phone_number_type]=local&filter[features][]=voice&filter[limit]=1" |
    jq -r 'first(.data[].phone_number) // empty')" || return 2
  [[ -n "$candidate" ]] || { carrier_error "Telnyx offered no US local voice number"; return 2; }
  telnyx_api POST /number_orders "$(jq -nc --arg p "$candidate" --arg c "$app_id" --arg r "$node_name" \
    '{phone_numbers: [{phone_number: $p}], connection_id: $c, customer_reference: $r}')" > /dev/null || return 2
  for attempt in $(seq 1 30); do
    number="$(telnyx_api GET "/phone_numbers?filter[phone_number]=${candidate/+/%2B}" |
      jq -c --arg p "$candidate" 'first(.data[] | select(.phone_number == $p and .status == "active")) // empty')" || return 2
    [[ -n "$number" ]] && break
    sleep 2
  done
  [[ -n "$number" ]] || { carrier_error "ordered Telnyx number is not active yet; re-run telephony:provision shortly"; return 2; }
  report telnyx number "bought $(jq -r .phone_number <<< "$number")"
  printf '%s' "$number"
}

ensure_telnyx_numbers() {
  local mode="$1" purchase="$2" app_id="$3" inventory profile='{}' roles role id number wanted
  local selected='{}' temp profile_path="$node_dir/telnyx-profile.json"
  inventory="$(telnyx_number_inventory)" || return 2
  if [[ -f "$profile_path" ]]; then
    profile="$(jq -ce --arg app "$app_id" 'select(.application_id == $app)' "$profile_path" 2>/dev/null)" || profile='{}'
  fi

  # Keep each valid saved role, including the receiver when the caller is missing.
  roles="$(jq -c --argjson p "$profile" --arg app "$app_id" '
    . as $numbers |
    def saved($id): first($numbers[] | select(.id == $id and .connection_id == $app and .status == "active") | .id) // "";
    {caller: saved($p.caller_number_id), receiver: saved($p.receiver_number_id)}
    | if .caller == .receiver then .receiver = "" else . end' <<< "$inventory")" || return 2

  for role in caller receiver; do
    id="$(jq -r --arg role "$role" '.[$role]' <<< "$roles")"
    number="$(jq -c --arg id "$id" 'first(.[] | select(.id == $id)) // empty' <<< "$inventory")"
    if [[ -z "$number" ]]; then
      number="$(jq -c --arg app "$app_id" --arg machine "$telnyx_machine_tag" --arg pool "$telnyx_pool_tag" \
        --arg mode "$mode" --argjson roles "$roles" '
        [.[] | select(.status == "active" and .id != $roles.caller and .id != $roles.receiver)
          | if .connection_id == $app then . + {priority: 0}
            elif $mode != "check" and ((.connection_id // "") == "") then
              if ((.tags // []) | index($machine)) != null then . + {priority: 1}
              elif ((.tags // []) | index($pool)) != null then . + {priority: 2}
              else empty end
            else empty end]
        | sort_by(.priority, .phone_number, .id) | first // empty' <<< "$inventory")" || return 2
    fi
    if [[ -z "$number" ]]; then
      [[ "$mode" == check ]] && return 1
      [[ "$purchase" == true ]] || {
        report telnyx "$role number" "missing (test pools exhausted; re-run with --allow-purchase to buy a US local number)"
        return 1
      }
      number="$(buy_telnyx_number "$app_id")" || return 2
    fi

    id="$(jq -r .id <<< "$number")"
    if [[ "$mode" != check ]]; then
      # A snapshot is not permission to take a number another app has since claimed.
      number="$(telnyx_api GET "/phone_numbers/$id" | jq -ce .data)" || return 2
      jq -e --arg id "$id" --arg app "$app_id" '
        .id == $id and .status == "active" and
        (.connection_id == $app or ((.connection_id // "") == ""))' <<< "$number" > /dev/null || {
        carrier_error "Telnyx number assignment changed during discovery; re-run telephony:provision"
        return 2
      }
      # Move machine affinity when reusing a shared number; preserve unrelated tags.
      wanted="$(jq -c --arg app "$app_id" --arg machine "$telnyx_machine_tag" --arg pool "$telnyx_pool_tag" \
        '{connection_id: $app, tags: (((.tags // [] | map(select(startswith($pool + "-") | not))) + [$machine, $pool]) | unique)}' <<< "$number")" || return 2
      if ! jq -e --argjson wanted "$wanted" \
        '.connection_id == $wanted.connection_id and ((.tags // [] | sort) == $wanted.tags)' <<< "$number" > /dev/null; then
        number="$(telnyx_api PATCH "/phone_numbers/$id" "$wanted" | jq -ce .data)" || return 2
        report telnyx "$role number" "assigned $(jq -r .phone_number <<< "$number")"
      else
        report telnyx "$role number" "found $(jq -r .phone_number <<< "$number")"
      fi
    else
      report telnyx "$role number" "found $(jq -r .phone_number <<< "$number")"
    fi
    roles="$(jq -c --arg role "$role" --arg id "$id" '.[$role] = $id' <<< "$roles")" || return 2
    selected="$(jq -c --arg role "$role" --argjson number "$number" '.[$role] = $number' <<< "$selected")" || return 2
  done

  if [[ "$mode" != check ]]; then
    mkdir -p "$node_dir"
    chmod 700 "$node_dir"
    temp="$(mktemp "$node_dir/.telnyx-profile.XXXXXXXX")" || return 2
    if ! jq -n --arg app "$app_id" --argjson roles "$roles" \
      '{application_id: $app, caller_number_id: $roles.caller, receiver_number_id: $roles.receiver}' > "$temp" ||
      ! mv "$temp" "$profile_path"; then
      rm -f "$temp"
      return 2
    fi
  fi
  printf '%s' "$selected"
}
