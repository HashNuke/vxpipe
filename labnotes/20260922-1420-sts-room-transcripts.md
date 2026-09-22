# STS room transcripts

## Baseline and scope

Previous goal turn made progress: native input checkpoint `a6615d91`, separate
format repair `447b3045`, and verification record `de2722da`. Current tree was
clean; all five root gates previously passed (2,185 tests, zero failures,
42 excluded; seed 0). No verification process remains live from that turn.

Continue directly per the user's later instruction, without delegation or
hosted/billable calls. Use discovery → milestone task breakdown → focused
red/green → commit → umbrella gates. New failures receive separate tasks and
repair commits rather than amendments.

## Inspection and plan

- Existing real-room PCM test proves provider caller/agent transcripts but
  not the human-STT or agent-output-STT combinations.
- `InputTurns.begin_audio_turn/4` still invokes `AgentOutput.interrupt/2` for
  recognized human onset; test whether delayed recognition can fence an STS
  reply already admitted by the provider's separate turn controller.
- STS room speech-start handling is a no-op to avoid double interruption;
  provider input turn-ended evidence currently has no room public-turn handler.
  Public caller turn events need a separate authorized projection.
- `SpeechToSpeech.Evidence.turn_key/1` exposes provider strings/inspected
  references as public correlation IDs. Pending public identity and exact-source
  association need explicit ownership, boundedness and stale-evidence tests.
- Added the room-transcript task breakdown and local design/dependency review
  to the milestone before tests or implementation. Start with all four caller/
  agent transcript-source combinations; do not mark broader B/C acceptance done.

## First reproduction

Added five real-room checks using 20 ms Morse units, separate human-STT/STS
input APIs, real PCM decode, sink settlement and the room event projection.
The four transcript-source combinations plus controlled room suspension produce
**five tests, two failures** (seed 0). Both agent-output-STT modes fail at
`CallEngine.start_call/1` with an unsupported `output_speech_to_text` path.

Cause: `PlanStartup.supported_speech/3` reads settings by capability role;
agent-output STT is a role using the existing STT registry, not a separate
provider-settings namespace. Later runtime resolution already uses STT settings,
so the earlier direct `PlanStartup.new/2` check missed the admission validator.
Added a specific repair task before implementation.

The delayed human-recognition scenario passes as-is: suspend RoomAuthority,
feed real human STT and STS input until the STS reply reaches the sink, then
resume the room and settle playback. `AgentOutput.interrupt/2` returns unchanged
when the ordinary text-model turn map is empty, so this interleaving does not
cancel the provider-driven reply. No interruption behavior change is justified
by this test. The room's missing provider caller-turn events remain separate.

## Repair and focused verification

- Added `PlanStartup.validate/2` to the existing output-STT activation check:
  **two tests, one expected failure** before implementation (seed 0).
- Normalize only the provider-settings kind for the agent-output role to
  `:speech_to_text`; preserve the selection role and its diagnostic path. No
  duplicate configuration section, fallback, dependency or credential change.
- Validator plus all five room checks pass after the repair (seven tests).
  Added missing/disabled-STT-provider rejection checks to guard host enablement.
- Complete focused group: **93 tests, 0 failures**, seed 0, from the Call Engine
  child. Includes PlanStartup directory, STS selection, existing STS room tests,
  new transcript combinations, room STS publication unit tests, input policy
  revision and STS capability/output-STT tests. Exact-file format checks pass.
- Updated milestone tasks, index and provider guide with the shared settings
  contract and bounded scope of the room evidence. Broader B/C/F tasks remain
  unchecked. Review/commit next, then all five root gates; no hosted calls.

## Committed checkpoint and root-gate result

Committed as `f213bfb5` before the broader gates. Root formatting,
warnings-as-errors compilation and strict Credo pass. The full test run completed
with 2,191 tests, two failures and 42 excluded (seed 0); both failures are in
Gateway's `HumanTransferWebRTCTest` (five-participant wait-cursor handoff and
`silent_all` release loss). Call Engine passes all 1,032 tests. The chained
unused-lock check was not reached because `mix test` exited with status 2.
The next milestone task records investigation and a separate repair checkpoint;
this run is not a successful umbrella gate. The test session was observed to
completion, not restarted on an observation timeout.
