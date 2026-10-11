# STT canonical-end fix (coordinator, fix3)

## Scope
- ONLY `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/stt_turn_start.ex` (coordinator)
  and `apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/stt_turn_start_test.exs` (tests).
- No commit. Pre-existing worktree changes left untouched (both target files were
  untracked `??` in `git status`; all other dirty/tracked files unmodified).
- Never read or modified `~/.config/vxpipe/live_providers.env`.

## Bug
Review-found canonical-end data loss in `STTTurnStart`:
- `settle_now/3` retained `last_text` internally but emitted `end_fields(canon, event)`
  with the raw (possibly blank) final text, dropping admitted interim words.
- `drain_one/2` emitted `end_fields(canon, final)` blank despite `pending_text`
  holding admitted interim words.

## Canonical-end rule implemented
- Nonempty provider final (trimmed-nonempty, exact bytes preserved, no trim/normalize)
  wins; otherwise backfill latest admitted nonempty same-turn text
  (`last_text` for active settle, `pending_text` for queued drain).
- No-word started acoustic turn (VAD onset, `last_text` nil): emits raw blank final
  text with provider endpointing (unchanged behavior).
- Unstarted no-word blank final: silent close + tombstone (unchanged).
- Request identity/duration/endpointing always come from the final event:
  end built as `end_fields(canon, %{event | text: end_text})`.
- Queued drain still uses the blank final's request identity for
  start/transcript/end (`effective_prid` path untouched).

## What worked
- Red-green-refactor followed strictly. RED: 4 new tests failed with exactly the
  expected assertion (`left: ""` / `left: "   "` vs retained interim text).
- GREEN: two-line-class fix (one `end_text` resolution in `settle_now/3`, one in
  `drain_one/2`); transcript dedup/revision logic untouched.
- Post-fix: 46 tests, 0 failures, also with `--seed 0`.
- `mix format` on the two files, then `--check-formatted` clean.
- `mix compile --warnings-as-errors` exit 0; `mix credo --strict` exit 0, no issues.

## Barriers
- `mix format --check-formatted` initially flagged the new tests (pipe-chain style);
  fixed with `mix format` on the two files, re-checked clean, re-ran suite green.
- Exit-code capture through a pipe needed a redirect-to-file pattern
  (`> file 2>&1; echo $?`) to report real tool exits.

## Decisions / rationale
- Backfill condition uses the existing `nonempty?/1` (trimmed-emptiness) predicate
  so whitespace-only finals are treated as empty, consistent with admission logic.
- No-word fallback keeps the raw blank final text (`last_text || event.text`,
  `pending_text || final.text`) rather than normalizing to `""`: minimal change,
  byte-for-byte provider evidence preserved, existing no-word tests unchanged.
- No refactor beyond formatting: the fix is two minimal expressions; any wider
  restructuring would risk the sealed-entry/retirement invariants.

## Deferred / out of scope (not fixed here)
- `Vxpipe.CallEngine.RoomAuthority.InputTurns.complete_audio_turn/4`
  (`apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/input_turns.ex:212-226`)
  unconditionally overwrites `turn.last_text` with `signal.text` (line 216) and
  commits/emits the raw text — a blank final would overwrite admitted interim words
  at that layer too. Left untouched per scope. New human STT uses canonical end text from the
  coordinator, so this downstream assignment now receives retained words. The
  historical native path deliberately keeps its previous behavior.

## Test evidence
- RED: `mix test test/vxpipe/call_engine/speech/stt_turn_start_test.exs`
  → 46 tests, 4 failures (canonical-end backfill assertions; guards passed).
- GREEN: same command → 46 tests, 0 failures; `--seed 0` → 46 tests, 0 failures.
- Bounds unchanged: `@max_turns 4`, `@max_controls 4`, `@max_retired 4096`;
  all overflow paths still return fixed `:turn_overflow` with no transcript text.

## Capacity fix (review follow-up): coordinator bound 4 → 9
- Review conflict: coordinator `@max_turns 4` vs Google STTSession bound
  (`apps/vxpipe_call_engine/lib/vxpipe/providers/google/stt_session.ex:14,258`:
  `@maximum_pending_turns 8` pending plus 1 active = 9 concurrent native turns).
  Correlating a 5th distinct native turn failed closed with `:turn_overflow`,
  so a full provider session (8 pending finals + 1 active) could not drain.
- Red-green-refactor followed strictly. RED: new test
  `"provider session capacity of eight pending finals plus one active drains
  in order"` (9 native `speech_started` hints, 1 active transcript + 8 queued
  transcripts, 8 queued finals sealed, then the active final drains all 8 in
  creation order with distinct canonical refs and outer-valid emissions)
  failed with exactly `{:error, :turn_overflow}` on the 5th hint under
  `@max_turns 4` → 47 tests, 1 failure.
- GREEN: `@max_turns 9` + moduledoc corrected from "(4, matching the inner
  provider session turn bound ...)" to "(9, matching the provider session turn
  bound of 8 pending finals plus 1 active ...)"; no other coordinator behavior
  changed → 47 tests, 0 failures, also with `--seed 0`.
- Bounds now: `@max_turns 9`, `@max_controls 4` unchanged, `@max_retired 4096`
  unchanged; fail-closed `:turn_overflow` overflow paths unchanged. Existing
  overflow tests use `max_turns()` dynamically so they still overflow at the
  new bound (10th distinct turn) and stay meaningful.
- Verification (from `apps/vxpipe_call_engine`): focused suite green,
  `mix format` on the two files then `--check-formatted` clean (exit 0),
  `mix compile --warnings-as-errors` exit 0. Root suite not run (parent owns it).
  The focused red run failed once; after the capacity change, all 47 coordinator tests passed, including seed 0. Both independent reviewers accepted the capacity amendment.
