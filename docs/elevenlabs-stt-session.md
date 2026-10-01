# ElevenLabs realtime STT session

Status: Session and scoped-service integration implemented on 2026-10-01.
Private credential resolution, publication, compiled room turns and rendered
Console configuration have local acceptance evidence. The configured-service
long-input live room case also passes. Other speech room checks pass locally;
final milestone verification passes under the approved STT/TTS scope.

## Decision

Use the allocation-owned acoustic runtime to supply genuine speech onset and
silence endpoints, and Scribe v2 realtime in manual mode to supply recognition.
The STT descriptor and projected room signal identify this boundary as
`local_gap`. This is acoustic gap authority, not semantic end-of-thought
detection or provider-reported VAD. The reviewed amendment is STT only: STS
controller admission and its existing evidence rules remain unchanged.

The detector confirms onset after four voiced 32 ms frames and endpoint after
sixteen silent frames, using the packaged runtime's fixed hysteresis. The input
assembler preserves the onset's four frames and includes the observed silence
confirmation in recognition audio. It retains incomplete PCM frames without
padding them or treating missing input as silence. Partials and commits never
create acoustic activity.

Each acoustic turn owns a fresh recognition connection. A long turn can contain
multiple serialized manual segments, each capped at twenty seconds of submitted
PCM. Only one commit is outstanding. The provider's
[commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
describes clearing a committed segment and retaining recognition context. That
context is deliberately confined to one acoustic turn.

A new acoustic turn can start before an older turn's recognition settles. Its
opaque reference is published immediately, while its PCM waits in the bounded
queue. Older partials and final text retain the older reference. After final
settlement the old connection is retired; any queued turn waits for its fresh
connection acknowledgement before audio is sent. Otherwise the next connection
is opened when the next turn's PCM is available. Late messages from retired
connections are ignored. Only initial readiness emits `ready` for the allocation.

Every open Scribe connection sends an empty, noncommitting `input_audio_chunk`
every ten seconds. This maintains the connection while no caller audio is
available. These protocol messages contain no PCM and do not advance detector
state, accepted caller usage, recognition segment budgets or acoustic duration.
They neither commit recognition nor manufacture silence or turn events. The
owned socket schedules them and retires its timer with its process. Other speech
socket callbacks retain their ordinary WebSocket ping unless they explicitly
provide a protocol keepalive frame.

## Ownership, admission and failure

The socket and detector supervisor are children of the allocation's provider
DynamicSupervisor. Model preparation uses that allocation's command Task
Supervisor. The shared cache contains only the immutable public model resource;
PCM, recurrent state, transcript assembly and turn references remain private to
the allocation. The channel is bound before preparation. Readiness requires
model preparation and the initial provider acknowledgement.

Admission owns at most one executing classification job, an ordered pending PCM
buffer, a 96,000-byte total retained PCM budget and four unsettled turns. The
budget includes pending input and the executing chunk, acoustic assembly and
queued recognition. Chunks are aligned 16 kHz mono S16LE PCM of
at most 32,000 bytes. Busy input is rejected without acceptance; accepted input
may later fail processing. Overflow, classifier failure, connection failure,
preparation deadlines and missing commit settlement retire the allocation with
a fixed safe reason. They do not manufacture final text. Empty initial partials
are harmless; empty committed text can settle only an outstanding commit.

The activity runtime retains a job slot through the worker's monitor-confirmed
termination, including the interval after result delivery. Only then does it
publish the outcome and admit replacement work. Its job budget controls native
concurrency; the owning task supervisor handles lifecycle without a second,
racing child quota. This permits ordinary room audio to queue during inference
while retaining bounded input and allocation cleanup.

Closing or replacing the allocation discards private audio/text and retires
inference, model preparation and sockets. Inspection hides credentials, PCM,
transcripts and native resources. `eager_end?`, `resume?` and `finite_input?`
remain false. Caller STT does not require optional agent-output drain support.

Accepted-input usage and acoustic turn duration are project observations, not a
claim about the provider's billed audio. Recognition sends a selected subset of
accepted PCM and includes genuine trailing silence. Scoped integration retains
the existing usage and permission-interval ownership.

## Scoped selection and Console configuration

The provider manifest declares credential, STT and TTS capabilities. The same
single API-key service supports Scribe recognition and ElevenLabs synthesis.
The standard encrypted tenant override or platform fallback is resolved privately
when starting a published call; its pinned plan and publication contain no key.

Caller selection is inline:

```json
{
  "speech_to_text": {
    "provider": "elevenlabs",
    "model": "scribe_v2_realtime",
    "credential_name": "voice",
    "options": {"language_code": "en"}
  }
}
```

Language is optional. The admitted recognizer fixes mono linear16 at 16 kHz
and manual recognition commits. Public authoring rejects other models,
commit strategies, sample rates, credentials and transport/classifier hooks.
Trusted runtime settings enable the session and supply the bounded media-ingress
budget. Provider usage and failure telemetry identify `elevenlabs` explicitly.

Platform and tenant service forms advertise STT/TTS and require only one API key.
The authoring catalog selects `scribe_v2_realtime` for STT; it advertises no
ElevenLabs STS capability. The forms truthfully leave credential-only testing
unavailable and direct verification through a call.

## Rejected alternatives and implications

- Provider commits as acoustic endpoints: the earlier long native-VAD experiment
  observed a commit during the repeated-speech phase. Commit cause is not supplied.
- First transcript as onset: recognition is not acoustic barge-in evidence.
- Reusing one connection across distinct acoustic turns: two selected live runs
  failed the known-word check. The diagnostic run recognized the first turn and
  returned empty text for the second. This does not establish the server's cause.
- Concurrent recognition connections for queued turns: serialized fresh contexts
  satisfy the current bounded queue contract. Connection preparation contributes
  latency and must be included in subsequent room acceptance.

The selected repair changes connection lifetime, not transcript assertions or
the user-visible STS contract. A brief first answer and a thirty-second initial
idle window now have separately selected passing evidence. This does not prove
an unlimited idle lifetime. Before milestone completion, verify scoped
replacement/usage, room consumers and Console metadata.

## Verification

The brief-first-answer case passes against the unchanged STT adapter: one test
in 3.0 seconds, seed 902523. A fixed 600 ms public "Yes." sample produces one
genuine onset, a matching local-gap end and recognized text without adding
padding. The separate initial-idle case initially fails after thirty seconds
without caller audio: the first submitted chunk is rejected as closed
(seed 762412). This does not establish the provider's exact disconnect reason.
With the empty, noncommitting protocol keepalive, the same selected idle case
passes in 32.3 seconds, seed 892995. Both earlier passing live cases are excluded.
The local protocol regression fails on a WebSocket ping before the repair;
afterwards the wire/peer-close/privacy group passes 29 checks, seed 477328,
including the existing ordinary TTS ping case.

The initial input/session lane failed seven checks before implementation.
STT admission/event/consumer checks failed three checks before `local_gap` was
implemented. Empty initial partial handling and fresh connection ownership each
had a focused failing check before their repairs. A defensive STS eager-event
check also failed before local evidence was fenced at that event boundary.

The session/input/descriptor group passes 21 checks, including actual packaged
CPU inference on the existing public PCM fixture, busy admission, bounded backlog,
twenty-second segment settlement, overlapping turn references, cancellation and
hard provider death. The separately selected repaired live case passes one test
in 9.0 seconds, seed 172613: two acoustic starts, distinct references, two settled
`local_gap` ends and the known public-fixture word in both. Passing this session
case does not establish scoped services or complete room acceptance.

The subsequent [scoped checkpoint](../labnotes/20261001-0427-elevenlabs-scoped-stt.md)
passes private selection/telemetry checks and thirteen persisted service/endpoint
checks. The compiled room check passes, seed 716606: twenty-one seconds of
deterministically classified voiced input cross a manual segment boundary;
the intermediate transcript stays nonfinal, the acoustic endpoint settles the
cumulative first turn, and a second caller turn receives a distinct index.
This verifies room composition with a local wire/classifier, not a hosted long
utterance or acoustic quality. The earlier native and selected live evidence
remain separate. TypeScript/lint and all 218 frontend checks pass. Rendered
Chrome inspection covers platform and tenant forms at 1440×1000 and 390×844,
including the tenant inventory and setup forms. Configured-service live room
acceptance remains required.

See [checkpoint labnotes](../labnotes/20261001-0230-scribe-local-session.md) for
terminal completion gates and remaining work. No passing paid case is repeated
by the default suite.

The [configured-room checkpoint](../labnotes/20261001-0505-scribe-configured-room.md)
passes one selected live case, seed 608205, in 25.8 seconds. A published room
resolves an isolated encrypted platform service through the production reader.
The 24.2-second public corpus forms one final room turn containing both the
earlier fixture word and the appended brief answer. Initial input first exposed
a failure; the [admission checkpoint](../labnotes/20261001-0522-scribe-input-admission.md)
adds ordered bounded PCM buffering and monitor-confirmed native worker retirement
with focused local red/green evidence. The original remote/native failure cause
is not asserted from the passing retry. Other provider room checks are recorded in
the [acceptance review](provider-expansion-acceptance.md). Final root and Lean
gates pass and coherent checkpoints publish the accepted STT/TTS milestone.
