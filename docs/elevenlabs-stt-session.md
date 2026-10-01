# ElevenLabs realtime STT session

Status: Session checkpoint implemented on 2026-10-01. Conversational service
registration, scoped credentials, compiled room startup, Console configuration
and final milestone acceptance remain pending.

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

## Ownership, admission and failure

The socket and detector supervisor are children of the allocation's provider
DynamicSupervisor. Model preparation uses that allocation's command Task
Supervisor. The shared cache contains only the immutable public model resource;
PCM, recurrent state, transcript assembly and turn references remain private to
the allocation. The channel is bound before preparation. Readiness requires
model preparation and the initial provider acknowledgement.

Admission owns at most one accepted classification chunk, a 96,000-byte retained
PCM budget and four unsettled turns. Chunks are aligned 16 kHz mono S16LE PCM of
at most 32,000 bytes. Busy input is rejected without acceptance; accepted input
may later fail processing. Overflow, classifier failure, connection failure,
preparation deadlines and missing commit settlement retire the allocation with
a fixed safe reason. They do not manufacture final text. Empty initial partials
are harmless; empty committed text can settle only an outstanding commit.

Closing or replacing the allocation discards private audio/text and retires
inference, model preparation and sockets. Inspection hides credentials, PCM,
transcripts and native resources. `eager_end?`, `resume?` and `finite_input?`
remain false. Caller STT does not require optional agent-output drain support.

Accepted-input usage and acoustic turn duration are project observations, not a
claim about the provider's billed audio. Recognition sends a selected subset of
accepted PCM and includes genuine trailing silence; future scoped integration
must retain the existing usage and permission-interval ownership.

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
the user-visible STS contract. Before milestone completion, verify short initial
utterances against the documented two-second processing threshold, initial idle
lifetime, scoped replacement/usage, room consumers and Console metadata.

## Verification

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

See [checkpoint labnotes](../labnotes/20261001-0230-scribe-local-session.md) for
terminal completion gates and remaining work. No passing paid case is repeated
by the default suite.
