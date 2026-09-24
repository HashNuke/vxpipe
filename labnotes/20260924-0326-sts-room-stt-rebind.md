# STS room STT rebind

Scope: prove a selected caller STT allocation rotates through a real RoomAuthority
source cutover and binds a fresh provider generation before WebRTC input reopens.
Use Morse STT/STS and a controlled in-process source-control peer; no hosted
provider or carrier/browser claim is involved.

## Design/dependency review (before tests/runtime)

The source-cutover owner remains `RoomAuthority`; selected STT producer signals
are private evidence and the connection-bound native `Ingress` is the only
caller-audio route to that recognizer. A transcript-policy interval replacement
must close that ingress locally before acknowledging the enforcer update. The
room consumes that invalidation, closes STS input, asynchronously fences the
exact source connection, and only then retires/rebinds a provider generation
when the policy transition permits it. `SpeechToText.input_binding/1` exposes
the provider allocation generation even when STT is transcript-only and has no
activity origin. Late `Signal`s from the same capability PID must compare that
generation before public caller-turn/transcript handling.

The integration regression will create a compiled call with Morse STS, selected
human STT, and a WebRTC source-control fixture. It will use a real policy
authority transition to force the native recognizer rotation, explicit hold/arm
ack barriers, and fresh PCM admitted only under the arm epoch. It will inject an
old-generation signal after the new binding and prove no public turn/text is
published. Existing fake source acknowledgements give deterministic control
without sleeping; actual Gateway receiver ordering stays covered by the prior
checkpoint's receiver/Connection tests.

This extends the recorded room-coordinator task in
`docs/milestones/agent-speech-to-speech.md`; selected external/hybrid transfer
overlap, full native acceptance, telephony and final umbrella gates remain
separate unfinished items.

## Progress

- [x] Red-test delayed provider-controlled old-generation STT evidence. The
  focused compiled-room red first published `ParticipantTurnStarted` from an
  old allocation generation after the current binding changed.
- [x] `InputTurns` now checks current native allocation generation for every
  selected STS transcript source. Provider-controlled mode does not require an
  activity origin; external/hybrid retain the exact audio-interval checks.
  The 29-test transcript-mode room file passes on seeds 0 and 1. A delayed
  same-capability STT event can no longer create a public caller turn after
  session replacement.
- [x] Compiled-room hold, fresh native binding and source-arm sequence with
  selected caller STT. A transcript-interval policy change rotates the source
  origin; the room closes both input lanes, sends a correlated hold to the exact
  source-control peer, waits for the fresh provider allocation generation,
  validates the receipt/token/attachment, arms, and reopens both lanes under the
  acknowledged source epoch. A delayed old-generation signal cannot open a
  caller turn, and a fresh caller turn still publishes exactly one caller pair
  and one `RECEIVED HI` reply.
- [x] The embedded `TestTransferConnection` now exposes a real hold/arm
  acknowledgement barrier (`complete_source_hold/2`, `complete_source_arm/2`)
  and threads `source_control?: true` into `CallEngine.attach_connection/3`.
  `Ingress` gained an explicit `:origin_notifier` (defaulting to `:owner` for
  test compatibility) so the source-origin invalidation reaches RoomAuthority
  instead of the media-drop observer. `Ingress.open/2` now accepts an explicit
  source epoch whenever source cutover is enabled, which a freshly created
  selected ingress needs.
- [x] Focused evidence: transcript-mode room file plus ingress file pass 51/0 on
  seeds 0 and 1; full Call Engine child suite passes 1,507/0 (30 excluded,
  seed 0). Full Gateway child run is not claimed here.
- [x] Re-run the ten-call measured lane after the rebind runtime change. All
  three modes pass (3 tests, 0 failures) in 25.2 seconds; each records 29 turns,
  ten interruptions, nine healthy survivors, and cleanup of all ten calls.
  Updated reports are in `20260924-0219-room-source-cutover-load.jsonl`. The
  embedded lane does not exercise this human-STT generation fence or WebRTC
  source cutover.
- [x] Root format check, warnings-as-errors compile, strict Credo (1,105 source
  files, no issues) and unused-dependency check pass.
- [x] Fail-closed source acknowledgements: a mismatched receipt and a
  source-rejected arm now retire the STS allocation (`SpeechToSpeech.stop`)
  while both input lanes stay closed, and a late arm cannot reopen them. Two
  compiled-room regressions pass; the transcript-mode plus ingress files pass
  53/0 on seeds 0 and 1, and the full Call Engine child suite passes 1,509/0
  (30 excluded, seed 0). A `nil` `policy_from` reply crash found by the first
  red is fixed with a pid guard. The ten-call measured lane passes in 25.4s.
- [x] Source loss and deadline fail closed: killing the source connection
  during the hold and injecting the room's own cutover deadline both retire the
  STS allocation, tear down the owning ingress tree (connection loss) or keep
  it closed (deadline), and reject a late acknowledgement. Transcript-mode plus
  ingress files pass 55/0 on seeds 0 and 1; the full Call Engine child suite
  passes 1,511/0 (30 excluded, seed 0). The ten-call measured lane passes in
  25.3s across `llm_tts`, `sts_provider` and `sts_output_stt`.
- [ ] Overlapping transfer hold, external/hybrid transfer overlap, telephony
  cutover, independent review and final umbrella gates remain open.
