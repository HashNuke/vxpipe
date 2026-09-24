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
- [ ] Red/green compiled-room hold, fresh native binding and source-arm sequence
  with selected caller STT; prove rebind and fresh PCM under the acknowledged
  source epoch while preserving caller transcripts when STS is unavailable.
- [x] Re-run the ten-call measured lane after this runtime change. All three
  modes pass (3 tests, 0 failures) in 25.4 seconds; each records 29 turns, ten
  interruptions, nine healthy survivors, and cleanup of all ten calls. Updated
  reports are in `20260924-0219-room-source-cutover-load.jsonl`. The embedded
  lane does not exercise this human-STT generation fence or WebRTC source cutover.
- [ ] Commit this focused STT evidence slice after root static checks.
