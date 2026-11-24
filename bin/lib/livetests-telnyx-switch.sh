# Sourced by bin/livetests. Keep number IDs locally across interruptions and renames.
switch_application_id() {
  local name="$1"
  telnyx_api GET "/call_control_applications?filter[application_name][contains]=$name&page[size]=250" |
    jq -er --arg name "$name" '
      select((.meta.total_pages // 1) <= 1) |
      [.data[] | select(.application_name == $name) | .id] |
      select(length == 1) | .[0] | strings | select(length > 0)'
}

switch_telnyx_numbers() (
  local mode="${1:-}" qa="${2:-$telnyx_qa_app}" journal="$node_dir/number-switch.json"
  local receipt qa_id test_id ids id from to current temp
  case "$mode:$#" in
    plan:1|plan:2|borrow:1|borrow:2|restore:1) ;;
    *) die "usage: telnyx:numbers plan|borrow [QA-application], or telnyx:numbers restore" ;;
  esac
  [[ "$qa" == "$telnyx_qa_app" ]] || die "expected QA application $telnyx_qa_app"
  [[ "$mode" == plan ]] || claim_owner
  load_credentials
  [[ -n "${TELNYX_API_KEY:-}" ]] || die "Telnyx credentials missing"

  umask 077
  mkdir -p "$node_dir"
  exec 9>"$node_dir/number-switch.lock"
  flock -x 9
  if [[ -f "$journal" ]]; then
    receipt="$(jq -ce 'select((.ids | type == "array" and length > 0) and
      (.qa_id | type == "string") and (.test_id | type == "string"))' "$journal")" || die "invalid switch journal"
    if [[ "$mode" != restore ]]; then
      jq -e --arg qa "$qa" '.qa == $qa' <<< "$receipt" >/dev/null || die "restore the existing loan first"
    fi
  else
    if [[ "$mode" == restore ]]; then echo "No borrowed numbers to restore."; return; fi
    qa_id="$(switch_application_id "$qa")" || die "cannot identify exactly one QA application named $qa"
    test_id="$(switch_application_id "$telnyx_test_app")" || die "cannot identify exactly one test application named $telnyx_test_app"
    ids="$(telnyx_test_inventory | jq -ce --arg app "$qa_id" '[.[] | select(.status == "active" and .connection_id == $app) | .id]')" || die "could not read number inventory"
    receipt="$(jq -nc --arg qa "$qa" --arg src "$qa_id" --arg dst "$test_id" --argjson ids "$ids" '{qa:$qa,qa_id:$src,test_id:$dst,ids:$ids}')"
    if [[ "$mode" == borrow ]]; then
      [[ "$ids" != '[]' ]] || die "no active numbers assigned to $qa"
      temp="$(mktemp "$node_dir/.number-switch.XXXXXXXX")"
      printf '%s\n' "$receipt" > "$temp"
      mv "$temp" "$journal"
    fi
  fi

  printf '%s: %s number(s) between %s and %s\n' "$mode" "$(jq '.ids|length' <<< "$receipt")" "$(jq -r .qa <<< "$receipt")" "$telnyx_test_app"
  [[ "$mode" != plan ]] || return 0
  from="$(jq -r .qa_id <<< "$receipt")"
  to="$(jq -r .test_id <<< "$receipt")"
  for id in "$from" "$to"; do
    local expected="$telnyx_qa_app"
    [[ "$id" != "$to" ]] || expected="$telnyx_test_app"
    telnyx_api GET "/call_control_applications/$id" |
      jq -e --arg id "$id" --arg expected "$expected" '
        .data | .id == $id and .application_name == $expected' >/dev/null ||
      die "application is outside this machine pool or could not be verified; switch journal retained"
  done
  if [[ "$mode" == restore ]]; then current="$from"; from="$to"; to="$current"; fi
  while IFS= read -r id; do
    current="$(telnyx_api GET "/phone_numbers/$id" | jq -er --arg id "$id" --arg machine "$telnyx_machine_tag" --arg test "$telnyx_test_tag" '.data | select(.id == $id and .status == "active" and ((.tags // []) | contains([$machine, $test]))) | .connection_id | strings')" ||
      die "number unavailable; switch journal retained"
    [[ "$current" != "$to" ]] || continue
    [[ "$current" == "$from" ]] || die "assignment changed externally; switch journal retained"
    telnyx_api PATCH "/phone_numbers/$id" "$(jq -nc --arg app "$to" '{connection_id:$app}')" |
      jq -e --arg id "$id" --arg app "$to" '.data | .id == $id and .connection_id == $app' >/dev/null ||
      die "assignment unconfirmed; retry or restore using the saved journal"
  done < <(jq -r '.ids[]' <<< "$receipt")
  if [[ "$mode" == restore ]]; then rm -- "$journal"; fi
)
