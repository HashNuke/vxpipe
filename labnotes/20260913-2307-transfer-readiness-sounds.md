# Transfer readiness and wait sounds

## Scope

Prepare the requested call-definition proposal and implementation milestone before runtime work.
Copy the user's original café-bossa and phone-ring WAVs into the owning Elixir application.
This checkpoint contains documentation and unchanged resource copies; no parser, media pipeline,
provider lifecycle, UI, or test implementation changes.

Created this log with `bin/create-labnotes transfer-readiness-sounds`. The existing root audio
files and the two earlier sound-authoring labnotes remain outside this checkpoint.

## Investigation and decisions

- Read the milestone index and the opening, agent-transfer, live-mixing, human-web-transfer,
  common-phone-transfer and usage prerequisites, their linked approved contracts, and incremental
  media policy design. Inspected definition/compiler/plan structures, startup readiness,
  `HumanHandoff`, `HumanCommitter`, transfer sideband promotion, opening asset preparation and
  WebRTC output pacing/completion.
- The engine currently completes a human handoff before Gateway promotion starts destination STT
  and main media. A common readiness barrier must precede media release and final success, covering
  all selected participant and room resources. A child PID alone does not prove readiness.
- Keep healthy capability generations and prepare only the actual resource/configuration diff.
  Waiting changes delivery gates; it must not cause unrelated provider or codec restarts. Real
  privacy changes continue to invalidate the affected intervals and queues.
- Each participant needs its own supervised playback cursor and bounded queue. Shared decoded
  bytes are appropriate; shared room playback would couple positions and leak private sounds.
  A recipient output arbiter must order waiting, briefing/opening, cue and room audio without
  restarting the negotiated transport timeline. Completion must acknowledge ordered delivery;
  neither enqueue nor a nominal-duration timer proves the cue preceded conversation.
- User clarification sets café-bossa for audiences transferring to an AI, phone-ring for audiences
  transferring to a human, and café-bossa for the receiving human after acceptance. Initial caller
  setup using phone-ring remains proposed. The two supplied loops are nine seconds long; the
  seven-second/three-second cursor acceptance example uses a separate ten-second fixture.
- The final schema proposal uses one call-level `wait_sounds` object with `call_setup`,
  `transfer_to_agent`, `transfer_to_human`, and `transfer_receiver`. Missing slots use defaults;
  a URL fetches that file; null / Elixir `nil` silences that slot. Whole-object null is proposed
  shorthand for silencing all waits. Earlier asset-name and participant-layer ideas were removed
  after the user required URL-or-nil call configuration. There is no `override` field.
- Keep missing and explicit null distinct through parsing, persistence and plan resolution.
  Reuse bounded fetch/address/cache primitives for configured URLs and pin prepared content for
  the call. Invalid files fail preparation explicitly. Bundled defaults remain internal local
  resources and do not require a URL or asset catalog from the application author.
- Copy assets to `apps/vxpipe_call_engine/priv/audio/wait_sounds/`, supporting web, phone and
  embedded hosts without Phoenix ownership. Existing `OpeningAudio.WaveDecoder` is mono-only;
  normalize the supplied stereo PCM16 sources once during future preparation, not on each loop.
- Insert the unchecked milestone before packaging. Preserve the packaging/retention review hold
  and existing completion states: 25 specifications, 21 complete, four pending.

## Separate local design review

Reviewed the proposal for scope, dependency order and missing contracts, separately from runtime
implementation. Covered all capability families and both resource scopes, multi-participant
audiences, independent cursors, receive-only listeners, private pre-room output, opening/briefing
priority, held-input discard, policy/readiness generations, reconnect cleanup, total attempt and
whole-call clocks, bounded recovery, partial-release failure, migration and safe telemetry.

The proposal explicitly identifies decisions still requiring review: initial caller ringtone,
acceptance only after briefing finishes, and cue playback for every held human listener including
the receiver. The latter two refine existing acceptance behavior and cue audience; they are not
represented as already approved or implemented. Wait-slot null never removes readiness or the
mandatory transfer cue. The beep itself will be generated during implementation.

No independent-agent review was performed. Planning approval must not check off implementation
acceptance or common gates. The new milestone records rejected alternatives and future browser
and phone verification requirements.

## Verification

- Python JSON parsing: the proposed complete definition parses; its four wait slots contain
  URLs or null, and stale configuration names are absent.
- Relative documentation check: 81 file/heading links resolve across the milestone, index and
  bundled-asset README. The index has consecutive entries, 21 complete and four pending; all
  explicit prerequisites occur before the new milestone. Runtime task/acceptance boxes are unchecked.
- WAV verification: both destination files are byte-identical to their root source, each
  1,728,044 bytes, 432,000 stereo frames, 48,000 Hz signed PCM16, nine seconds. SHA-256:
  - `cafe-bossa.wav`: `c20f5348c47cd92d5d9ef6206a37ae9bcbad16f3767b4d92b392a0eb334f6aad`.
  - `phone-ring.wav`: `3e7b1bc36207074e140393b1d769f1868e8b10979ed4b519a5ff72e2b1a82157`.
- `git diff --check` passes. Inspect exact staged paths and the staged diff before committing.
- No tests were written. No application code changed, so no Mix, browser or live-provider checks
  were run for this planning/resource-copy checkpoint. Those checks remain runtime acceptance gates.
