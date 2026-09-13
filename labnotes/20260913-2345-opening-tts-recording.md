# Opening TTS and recording

## Requested outcome

Text opening audio must explicitly select its own TTS profile, work with a human initial
receiver, and never inherit an agent's voice. Verify and fix the suspected recording leak
during opening playback. Preserve unrelated root sound assets and earlier sound labnotes.

## Recording checkpoint

- Inspected opening input admission, Gateway's parallel STT/room-audio delivery, room mixing
  and the recording subscriber. STT had the opening gate; decoded room audio bypassed it.
- Added a room-level recording regression using the real mixer and recording subscriber with
  an injected writer. First corrected the fixture to use the authoritative per-source policy
  interval; then the intended red failure showed two delivered frames (full mix and individual
  track) before playback completion where zero were expected.
- Initialize the mixer with a closed opening gate when the pinned plan has an announcement.
  Actual opening completion opens that gate before STT/greeting admission. Record the opening
  completion timestamp in the mixer's existing clock domain so late-decoded held frames cannot
  be admitted after the gate opens. The gate also protects the recording-egress path. No media
  policy revision or provider restart is introduced.
- The new regression is green: start/progress/enqueue do not permit recording, delayed audio
  from the held interval remains discarded, and subsequent caller audio reaches both recording
  streams. Existing focused opening/mixer/recording coverage: 26 tests, zero failures.
- Root gates pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test` (1,008 tests, zero failures), and
  `mix deps.unlock --check-unused`. No browser/UI changes were made in this checkpoint.
  The following checkpoint implements independent opening TTS.

## Independent TTS checkpoint

- User approved replacing the initial-agent voice entirely, including direct entry to a human
  receiver. Read the current opening contract, architecture, G7 decision, prepared admission,
  background-tool prerequisite and actual compiler/runtime/persistence paths before changing them.
- Schema `20260913.01` requires `opening_audio.text_to_speech` for text sources: a reference to the
  existing closed capability-profile registry. File sources reject that field. The compiler pins
  a separate resolved opening source/selection. No participant/default/legacy voice fallback is
  retained. Current config and fixtures use the new schema; migration guidance requires updated
  definition revisions and repreparing unstarted old plans rather than modifying historical data.
- First compiler red run rejected the new explicit field and still accepted missing selection.
  After parser/resolver changes, the focused compiler tests passed. The new human-entry runtime
  test then exposed the old runtime opening type and its receiver-TTS coupling.
- Opening playback now owns a separately supervised TTS capability, scoped to the entry caller
  with no agent activation. It is monitored separately from agent TTS and released on successful
  text or cached playback completion; room supervision handles failure cleanup. Only that owned
  capability's callbacks can complete/fail text opening. Agent greeting speech retains its own
  provider and process. File playback needs neither TTS nor a receiver-derived identity.
- Runtime tests prove human entry, distinct opening/greeting models, cleanup via a process
  monitor, absent resolved selection rejection, and required-playback failure. A cache regression
  initially reused audio from a different selected profile reference; including the explicit
  profile in the public output identity fixes it while retaining same-profile cache reuse.
- Extended the existing real-PostgreSQL prepared-call reconstruction test with a configured
  opening profile and pinned options. It passes (one focused test). No storage format fallback
  or migration that invents a voice was added.
- Extended the recording regression to both file and text openings, offering announcement
  egress as well as caller ingress to the actual mixer/recording boundary. Neither output nor
  caller speech is recorded before actual completion; delayed held caller frames stay excluded;
  subsequent caller frames reach full-mix and individual tracks. The opening room file passes
  with 14 tests. The earlier combined compiler/runtime/cache check passed with 24 tests before
  the second recording-source case was added.

## Separate design review

Reviewed profile syntax/resolution, closed provider ownership, privacy-safe inspection, no-agent
entry, callback identity and cleanup, cache/tenant binding, pinned plan reconstruction and schema
migration. Reviewed recording at both room ingress and accepted egress, with positive recording
after release and exclusion of late held frames. The implementation preserves media policy
intervals and unrelated capability lifetimes. Updated the owning contract, architecture, G7
decision and milestone sources; wait-sound implementation remains outside this approved change.

Unrelated sound-authoring files were moved/staged concurrently by other work. The recording fix
was committed with exact paths using `git commit --only`, preserving those staged changes.

Final verification after the complete recording regression expansion:

- `mix format --check-formatted`: passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: passed, 807 source files, no issues.
- `mix test`: passed, 1,013 tests, zero failures; existing integration exclusions remain.
- `mix deps.unlock --check-unused`: passed.
- Three JSON documentation examples parse; 22 relative file/heading links resolve across the
  changed opening contract and milestone documents. `git diff --check` passes.

No rendered browser or live-provider check is claimed: this checkpoint changes backend
lifecycle/schema and the sample's schema version, not UI behavior or layout.
