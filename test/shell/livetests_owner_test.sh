#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d -t vxpipe-livetests-owner.XXXXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Real, isolated Git worktrees; every external command and credential is synthetic.
mkdir -p "$scratch/a/bin/lib" "$scratch/fake"
cp "$repo_root/bin/livetests" "$scratch/a/bin/"
cp "$repo_root/bin/lib/"livetests*.sh "$scratch/a/bin/lib/"
git -C "$scratch/a" init -q -b owner-a
git -C "$scratch/a" add bin
git -C "$scratch/a" -c user.name=Fixture -c user.email=fixture@example.test commit -qm fixture
git -C "$scratch/a" worktree add -qb owner-b "$scratch/b"
export VXPIPE_LIVETESTS_STATE_DIR="$scratch/state"
export VXPIPE_LIVE_PROVIDERS_ENV_FILE="$scratch/credentials"
export VXPIPE_LIVE_PROVIDERS_MIX_BIN="$scratch/fake/mix"
export VXPIPE_LIVETESTS_TAILSCALE_BIN="$scratch/fake/tailscale"
export VXPIPE_LIVETESTS_TAILSCALED_BIN="$scratch/fake/tailscale"
export VXPIPE_LIVETESTS_CURL_BIN="$scratch/fake/curl"
export OWNER_TEST_MARKER="$scratch/started"
printf ': > "$OWNER_TEST_MARKER.credentials"\n' > "$scratch/credentials"
cat > "$scratch/fake/mix" <<'MIX'
#!/usr/bin/env bash
: > "$OWNER_TEST_MARKER"
if [[ "${OWNER_TEST_INTERRUPT:-}" == yes ]]; then kill -TERM $$; fi
exit "${OWNER_TEST_STATUS:-0}"
MIX
printf '#!/usr/bin/env bash\nexit 1\n' > "$scratch/fake/tailscale"
printf '#!/usr/bin/env bash\n: > "$OWNER_TEST_MARKER.provider"\nexit 1\n' > "$scratch/fake/curl"
chmod +x "$scratch/fake/"*
run_a() { "$scratch/a/bin/livetests" "$@"; }
run_b() { "$scratch/b/bin/livetests" "$@"; }
owner_is() { [[ "$(cat "$scratch/state/owner")" == "$1" ]] || fail 'wrong owner'; }
refused_b() {
  rm -f "$scratch/started"*
  if run_b "$@" > "$scratch/out" 2>&1; then fail "other branch accepted: $*"; fi
  rg -q owner-a "$scratch/out" || fail 'owner not explained'
  [[ ! -e "$scratch/started" && ! -e "$scratch/started.credentials" && ! -e "$scratch/started.provider" ]] || fail 'refusal came after side effects'
  owner_is owner-a
}
run_a run --only live_openai
[[ -f "$scratch/state/owner" ]] || fail 'first use did not claim ownership'
cmp -s "$scratch/state/owner" <(printf 'owner-a\n') || fail 'owner is not just a branch name'
run_a run --only live_openai
owner_is owner-a
for selection in live_openai live_deepgram live_telephony live_twilio live_telnyx live_providers; do
  refused_b run --only "$selection"
done
refused_b run
printf 'TELEPHONY_TEST_PUBLIC_URL=https://fixture.example.test\n: > "$OWNER_TEST_MARKER.credentials"\n' >> "$scratch/credentials"
refused_b run --only live_telephony
for command in tools:up tools:down telephony:provision telephony:hangup telnyx:hangup twilio:hangup release; do refused_b "$command"; done
run_b tools:status > "$scratch/out"
run_b telephony:status > "$scratch/out" 2>&1 || true
if rg -q 'belongs to branch' "$scratch/out"; then fail 'read-only status was restricted'; fi
owner_is owner-a
# Missing credentials and failing/interrupted child commands retain the owner.
rm "$scratch/credentials"
if run_a run --only live_openai > "$scratch/out" 2>&1; then fail 'missing credentials accepted'; fi
owner_is owner-a
: > "$scratch/credentials"
status=0
OWNER_TEST_STATUS=7 run_a run --only live_openai || status=$?
[[ "$status" == 7 ]] || fail 'lost child status'
owner_is owner-a
status=0
OWNER_TEST_INTERRUPT=yes run_a run --only live_openai || status=$?
[[ "$status" == 143 ]] || fail 'lost signal status'
owner_is owner-a
run_a release
[[ ! -e "$scratch/state/owner" ]] || fail 'release retained claim'
run_b run --only live_openai
owner_is owner-b
run_b release
# Concurrent initial claims must publish exactly one complete branch name.
for attempt in 1 2 3 4 5; do
  (run_a run --only live_openai > "$scratch/a.out" 2>&1; echo $? > "$scratch/a.status") & a=$!
  (run_b run --only live_openai > "$scratch/b.out" 2>&1; echo $? > "$scratch/b.status") & b=$!
  sa=0; sb=0
  wait "$a" || sa=$?
  wait "$b" || sb=$?
  [[ $((sa + sb)) == 1 ]] || fail 'concurrent claims did not select one owner'
  if [[ "$sa" == 0 ]]; then owner_is owner-a; run_a release; else owner_is owner-b; run_b release; fi
done
# Detached checkout fails before loading credentials or starting Mix.
git -C "$scratch/b" checkout -q --detach
rm -f "$scratch/started"*
if run_b run --only live_openai > "$scratch/out" 2>&1; then fail 'detached checkout accepted'; fi
rg -qi 'named branch' "$scratch/out" || fail 'detached recovery missing'
[[ ! -e "$scratch/state/owner" && ! -e "$scratch/started" ]] || fail 'detached checkout had side effects'
printf 'livetests ownership checks passed\n'
