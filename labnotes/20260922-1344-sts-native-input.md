# STS native input

## Scope and workflow

Continue directly on `sts-impl`, after the committed room-input checkpoint.
Wire separately prepared STS microphone conversion into WebRTC and telephony;
leave Google hosted calls and advertisement gated. No delegation or paid calls.
Follow focused checks → coherent commit → umbrella gates; fixes get separate
commits. User additionally requires every new finding/addition to be recorded
and broken into milestone tasks before implementation starts.

Implementation paused on that clarification: the converter helper already
existed with four green tests and two new callback tests were red. Added the
native microphone task breakdown and local design/dependency review to
`docs/milestones/agent-speech-to-speech.md` before continuing. Future findings
must be added there first, including discoveries during verification.

## Evidence so far

- Initial four `media/sts_input_test.exs` checks failed with the expected missing
  `STSInput.prepare/4` boundary (seed 0).
- Added `Gateway.Media.STSInput`; reused existing native converters with state
  separate from human STT. Generalized telephony normalizer preparation to
  accept the source track map as well as a frame.
- The four tests pass (seed 0): stereo WebRTC Opus48k → monoPCM16k, Telnyx
  Opus16k → PCM16k, Twilio PCMU8k → PCM16k, explicit unsupported/missing
  allocation errors; WebRTC wraparound and late-packet rejection included.
- Two subsequent native callback tests fail as expected on missing
  `:speech_to_speech_track` handlers (six tests, two failures, seed 0).
- No native transport adoption or root-gate success is claimed yet. All tests
  above ran from the Gateway child with real local codecs and a supervised
  Call Engine STS ingress; they are not carrier/network interoperability tests.

## Design

Conversion belongs to the transport connection; credit, policy, source identity
and bounded admission remain in Call Engine. A private handle alone does not
mean STS is selected: readiness demand must resolve its real allocation before
preparing the converter. Extend only WebRTC's RTP sequence at the STS boundary;
telephony already supplies monotonic sequence numbers. Unsupported transfer
candidate preparation must fail explicitly until the milestone's handoff work.

## Native checkpoint evidence

- Both new callback tests turned green: WebRTC retains sequence state across
  callbacks; the telephony session drops denied STS audio and accepts later
  permitted input after a policy revision. Malformed/receive-only regressions
  also pass (14 tests at that stage).
- Readiness initially failed for a test-fixture error: the supervisor PID was
  mistaken for its media-session child. Corrected it to use the transport's
  readiness resource. Re-ran against the original readiness implementation:
  the STS-only graph failed with `:invalid_input_track`, the expected missing
  demand behavior. Restored the readiness change and used the existing
  `TestCallStartup.await_open/1` acknowledgement before inspecting the async
  allocation. An embedded fixture's `:test_call_ready` message is not emitted
  by a native phone session; do not wait for that message in native tests.
- The supervised phone room now opens without human STT. Its STS-only graph
  contains the input track and exact policy-bound STS ingress. Missing handle
  and a newer, unprepared policy revision fail explicitly.
- Four additional local integration checks retain delivery credit in one real
  ingress and verify delivery through the other: WebRTC and telephony, each
  with STT blocked and with STS blocked. No sleeping or mailbox-growth probe
  substitutes for the explicit credits/acknowledgements.
- Unsupported STS candidate preparation fails before media preparation.
- After green callback tests, moved WebRTC input helpers into IncomingAudio to
  retain the connection's existing size/SRP boundary (769 lines). This finding
  was added to the milestone before refactoring.
- Formatted exact changed Elixir files. Final focused Gateway regression group
  passes **43 tests, 0 failures**, seed 0: STS input, room ingress policy,
  telephony session/conversion, WebRTC connection/incoming/speech conversion.
- Reviewed implementation and focused diffs. No dependency, credential, hosted,
  UI or provider-advertisement changes. Commit precedes root gates; those gates
  remain pending at this checkpoint.

Limitations: native input/readiness checks are not full multi-mode conversations,
carrier interoperability, rendered-browser verification, a ten-call load or
complete room transfer/hold/recording/usage acceptance. Milestone remains open.
