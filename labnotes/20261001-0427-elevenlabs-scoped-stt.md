# ElevenLabs scoped STT

## Intent

Register the admitted allocation-owned Scribe Realtime session through ordinary
Call Spec selection, scoped credentials, compiled rooms and platform/tenant
service configuration. Hosted-agent STS remains deferred. Preserve fixed manual
segmentation and local acoustic turn ownership; expose only language selection
as an optional public STT setting.

## Focused red/green evidence

- Selection first fails: two tests, one failure, seed 21863; the manifest does
  not yet declare STT. Public authoring rejects unsupported/private options.
- Persisted service activation first fails: one test, one failure, seed 419472;
  publication rejects the Scribe provider/model selection.
- Frontend catalog/onboarding first fails: two failures, seven passing tests;
  ElevenLabs advertises only TTS.
- Attribution first fails: nine tests, three failures, seed 317557; ElevenLabs
  speech and Cartesia STT are labelled `other`.
- After registration/private configuration changes, selection and attribution
  pass eleven tests, seed 503996. Persisted platform fallback, tenant override,
  deletion fallback and endpoint metadata pass thirteen tests, seed 81583.
- Frontend catalog/onboarding pass all nine focused tests.

## Decisions

The single API-key schema already used by TTS also supplies STT. Public Call
Specs carry model/language selection, never API keys or wire/classifier hooks.
Private trusted settings retain test seams without allowing them through authoring.
Usage and bounded telemetry identify ElevenLabs explicitly; the adjacent missing
Cartesia STT attribution is repaired at the same boundary.

## Verification in progress

Compiled room audio/turn acceptance, rendered STT service forms and final umbrella
gates remain unverified at this checkpoint. Existing paid short-answer, two-turn
and initial-idle cases are not repeated. A configured-service room live case is
still required before milestone completion.

Chrome initially fails with an unavailable OS sandbox. An isolated named browser
session launched with the CLI's browser-args environment override succeeds; this
is a local browser-launch workaround, not an application change.

## Compiled room and rendered forms

The new owning CallEngine room test compiles a caller Scribe selection and starts
it through the scoped credential source and normal connection ingress. It passes
one test, seed 716606: twenty-one seconds of deterministic voiced classification
cross a twenty-second manual segment boundary, an intermediate segment stays
nonfinal, the supplied acoustic gap settles cumulative text, and a second turn
settles under the next room turn index. Fresh wires retire under monitoring.
This uses a local wire/classifier; it does not claim hosted long-input acceptance.

Test construction initially used public participant keys instead of resolved
participant IDs, and observed an ingress readiness binding retired by normal
room adoption. Correct the attachment identity and collect the provider resource
as the existing room harness does. A further assertion lacked enough completely
silent classifier frames after a mixed frame; retain PCM framing and provide
576 ms of genuine quiet input. No production turn logic changes are needed.

Full frontend verification initially exposes two stale TTS-only modal assertions:
216 pass and two fail. Update the expected STT badge while retaining no-STS,
single private key and scope-save assertions. The rerun passes all 218 checks;
TypeScript and lint pass.

Rendered Chrome inspection covers platform, tenant setup and tenant inventory
single-key forms at desktop 1440×1000 and phone 390×844. Setup forms show STT/TTS
badges, no STS, one blank API-key input and the existing truthful unavailable
credential-probe state. Phone controls remain visible and usable. This is
Storybook rendering; persisted API behavior is verified separately above.

Format, warnings-as-errors compile, strict Credo (1,176 sources), unused-dependency
checking and the Lean build/oracle/replay pass; the latter reports one test,
seed 497812. The first default umbrella run terminates with one failure among 3,020 tests
(96 excluded), seed 232973. The existing STS source-arm rejection observation
times out; all other apps pass, including 522 Gateway checks. The bounded test
correction and owning 37-test rerun are recorded in
[source-arm labnotes](20261001-0454-source-arm-deadline.md). A full final root
rerun with the same seed passes all 3,020 reported tests, zero failures and
96 exclusions. This includes all 1,812 CallEngine, 522 Gateway and 194 Console
checks. The completed root gate verifies the scoped STT checkpoint; configured
service live room and final milestone acceptance remain pending.
