# TTS timing and spoken transcripts

Status: proposed contract, 2026-11-16. Research and source inspection only;
no adapter, persistence or history behavior has changed. Delivery belongs to A/B
and the broader F acceptance in the
[combined voice milestone](../../labnotes/milestones/voice-agent-turns-and-listening.md).
The runtime policy in the [classifier proposal](barge-in-classifier.md) can use
this evidence internally when available; neither the text classifier nor the
LLM receives playback diagnostics, and the policy must work without timing.

## Decision

Retain generated assistant text separately from the transcript of delivered
speech. If the model generated `x y z` and playback stopped after `y`, preserve
`x y z` as generated output and project `x y` as the interrupted spoken turn,
when provider timing and playback evidence support that boundary. Ordinary LLM
conversation context uses only the spoken projection. The full generated response
and playback evidence remain application records, not extra LLM context.

This is an optional provider/model capability, as requested by the user. Absence
of alignment must not disable a provider, delay playback/cancellation, trigger a
new model request or manufacture word timings. Retain the existing coarse
completed-segment behavior with explicit uncertainty for an interrupted segment.

The integrations normalize provider timing into one typed speech contract before
participant services consume it. Call Engine combines that contract with output
playback progress. Neither providers nor participant policies independently edit
conversation history.

The [structured message protocol](structured-agent-messages.md) supplies explicit
speaker/event attribution and typed assistant history. A provider `assistant`
role alone is not delivery evidence; its projected participant message carries
only supported spoken text and ordinary identity/intent fields. Delivery metadata
stays internal. The model's decision stays separate from actual playback.
The [message-format milestone](../../labnotes/milestones/structured-agent-messages.md)
owns that generic/coarse projection; this specification and the voice milestone
add provider timing, precise cutoff evidence and voice-specific settlement.

## Current implementation and evidence

- [AgentOutput](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/agent_output.ex)
  publishes generated `TextOutput` segments before synthesis. On completed
  playback it records the whole segment as delivered and appends it to
  [SpokenHistory](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/spoken_history.ex).
  Discarded segments do not append a timed partial prefix. Interruption records
  a played duration, not a word-level spoken transcript.
- [Archive projection](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/archive/event_projection.ex)
  already distinguishes generated text from delivery events. Durable retention
  depends on the archive port and source policy; it is not guaranteed for every
  room. [Archive policy](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/archive/policy.ex)
  strips transcript text when saving transcripts is disabled.
- [RequestRunner](../../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/request_runner.ex)
  places a completed model response in session conversation state. That is not
  an immutable disk record: [interruption handling](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/agent_runtime/coordinator/interruption.ex)
  discards eligible exchanges by correlation. The
  [output buffer](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/agent_runtime/output_buffer.ex)
  retains streamed text while assembling sentences; inspection did not establish
  archival coverage for an unfinished buffered sentence cancelled mid-generation.
- [ElevenLabs TTS](../../apps/vxpipe_call_engine/lib/vxpipe/providers/elevenlabs/tts.ex)
  decodes audio/final events but does not carry alignment through the speech
  boundary. [Rime TTS](../../apps/vxpipe_call_engine/lib/vxpipe/providers/rime/tts.ex)
  explicitly ignores `timestamps` events. There is no shared TTS timed-span
  capability today; existing STS output transcript fields are not that contract.
- [Gateway output](../../apps/vxpipe_gateway/lib/vxpipe/gateway/media/audio_output.ex)
  tracks paced frame delivery. Its [remote clear acknowledgment](../../apps/vxpipe_gateway/lib/vxpipe/gateway/media/audio_output/remote_playback.ex)
  returns the locally captured played count. This is not an independent
  measurement of the remote listener's speaker position. The proposed feature
  must preserve that distinction rather than rename local egress as hearing.

## Provider capabilities

Primary references checked 2026-11-16; no live timing accuracy was measured.

| Integration | Available timing | Normalized evidence |
| --- | --- | --- |
| ElevenLabs TTS WebSocket | Character alignment; `sync_alignment` synchronizes alignment with returned responses. The integrated multi-context API also exposes that option. | `provider_alignment`; retain character spans and derive language-appropriate word boundaries where supported. Verify clock origin and actual frame shapes on the integrated endpoint. |
| Rime Coda legacy `/ws3`, currently integrated | Estimated word starts/ends in seconds, per synthesis batch, after its first audio chunk. The documented estimates are not aligned to generated audio. Returned for English/Spanish or omitted `lang`, with other languages potentially returning none. | `provider_estimate`; useful for an approximate prefix, never promoted to precise alignment by normalization. |
| No timing for the selected provider/model/language/request | Audio can still stream and complete normally. | `unavailable`; no word-level truncation claim. |

Sources: [ElevenLabs TTS alignment](https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-stream-input),
[multi-context options](https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-multi-stream-input),
[Rime `/ws3` timing contract](https://docs.rime.ai/api-reference/coda/websockets-json.md).

Rime's newer [Coda WebSocket](https://docs.rime.ai/api-reference/coda/websocket-v1.md)
offers aligned words on `done`, after audio delivery. It is not the integrated
endpoint and must not be assumed to provide incremental alignment. Deepgram
[Flux TTS](https://developers.deepgram.com/reference/text-to-speech/speak-flux)
reports spoken/remaining text after an interrupt with a supplied playback offset;
that is a separate settlement capability, not a continuous timed-word stream.
Neither endpoint migration is required by this proposal.

## Common optional timing contract

Suggested contract: `Speech.OutputAlignment`, emitted as a bounded semantic
event through the existing speech channel, with normal allocation/permission
acknowledgment. Final module/event names can follow implementation conventions;
the following semantics are required:

| Field group | Contract |
| --- | --- |
| Identity | Existing room/activation/allocation/request/output identities and output generation, plus synthesis-segment identity. Provider context IDs are mapped inside the adapter, not trusted as room identity. |
| Version and ordering | Schema version, monotonic alignment revision and immutable text for that revision. A new revision replaces the scoped alignment snapshot; duplicate deliveries do not append duplicate text. Bound bytes/spans and reject retired identities. |
| Text | Text actually described by the spans, with `text_basis` distinguishing original input from provider-normalized speech. Preserve original generated text independently. |
| Spans | One common list of `text_start_byte`, `text_end_byte`, `audio_start_ms`, `audio_end_ms`, with `unit` equal to `character` or `word`. Text ranges are half-open UTF-8 byte ranges into that revision, validated at Unicode boundaries. |
| Audio clock | Nonnegative integer milliseconds relative to the canonical output's decoded audio timeline. Convert provider seconds and chunk/context/segment-relative origins inside the integration, keeping rounding conservative at cutoffs. Missing clock mapping means unavailable evidence. |
| Quality and coverage | `provider_alignment` or `provider_estimate`, provider/model provenance, and whether coverage is partial or complete. Missing spans are not silent words; zero-duration punctuation does not establish audible speech. |
| Capability | Descriptor declares supported granularity, quality and delivery phase (`streaming` or `on_completion`) per profile. Each request may still report unavailable data. A capability declaration alone does not prove receipt. |

Normalize time units and identity, not evidence quality. Participants do not parse
ElevenLabs character arrays or Rime `word_timestamps`. Shared projection code can
derive word boundaries from character spans, with explicit language rules;
space splitting alone is insufficient for all supported languages.

Provider normalization may turn `22` into `twenty two`, and SSML can add unspoken
markup. Project the aligned rendered text. Map it back to original text only
where a validated mapping exists; do not slice the original string by normalized
character counts. Retain segment offsets across chunk boundaries and synthesis
batches, including silence and any audio conversion. If the provider clock
cannot be mapped to the played output, mark that mapping unavailable.

## Playback settlement and spoken projection

Alignment answers where text falls in generated audio. A separate playback
observation answers how far output progressed. Keep its scope, output identity,
audience, cutoff and evidence kind (`client_playback`, `local_sink`,
`transport_egress`, or `unavailable`) alongside alignment quality. Even a client
playback report is not proof of human perception.

1. Accumulate generated text and timing under the exact response/output identity.
   Audio must not wait for optional alignment. A response still generating at
   cancellation retains only what it actually produced, marked incomplete;
   do not keep generation running merely to obtain an unspoken suffix.
2. On accepted interruption, use the existing bounded output-clear/settlement
   boundary. Capture the final supported playback cutoff, including audio that
   progressed after human onset while the interruption decision was pending.
   Onset time, cancellation-request time and final playback position differ.
3. Build the longest contiguous covered prefix ending at a complete word whose
   end is within that cutoff. Keep earlier completed segments; exclude queued
   segments and unplayed suffixes. A cutoff in the middle of `y` must not claim
   the whole word `y` was spoken. Preserve partial-span evidence separately.
4. Publish a replacement/revision of the same assistant spoken turn, with
   interrupted status, timing quality and playback evidence. Do not create a
   second assistant turn or overwrite generated-output evidence.
5. Before admitting the next ordinary LLM request, settle its conversation
   projection once from evidence already available. Do not add a new alignment
   wait to cancellation or turn processing. Missing optional data takes the
   explicit fallback below. Late data may correct archive/UI transcript projections
   through a correlated revision, but never rewrite a committed model-history
   message or submitted request, resurrect playback or change a newer response.
   Do not append speech_delivery or speech_delivery_correction events to model
   history. A later improved archive/UI prefix need not match the earlier frozen
   model prefix; this is the explicit simplicity/append-only tradeoff.

A telephony clear acknowledgment can include disposal of buffered output. It
must not be treated as proof that the cleared buffer played. For fan-out, scope
playback evidence to the listener whose conversation is being projected; do not
use the most advanced recipient's position as proof for all recipients.

For the user's example, if word ends are `x=100 ms`, `y=250 ms`, `z=400 ms` and
the supported cutoff is `300 ms`, the spoken text is `x y`. `z` may have begun,
but it is not a fully delivered word. With estimated alignment or a local-only
cutoff, label that prefix estimated/qualified; do not promise exact remote hearing.

## Retention, transcript and LLM context

Keep three explicit representations:

| Representation | `x y z` interrupted after `y` |
| --- | --- |
| Generated output | `x y z`, unchanged, with complete/incomplete generation status. |
| Spoken transcript | `x y`, interrupted, with timing quality and playback provenance. |
| Ordinary LLM conversation | `x y` in the ordinary assistant content, without playback metadata; `z` is not represented as previously communicated. |

The structured interruption decider receives minimal participant text/mode and
ordinary permitted conversation history. It does not receive generated-versus-
played fields, status, timing quality, provenance or classifier diagnostics.
The application owns that evidence and response admission. The common response
uses agent_mode and nullable message for dialogue, with native idle handling
explicit stop-and-wait. Only admitted message text reaches TTS; mode/purpose and
idle acknowledgment do not expose timing metadata to the model.

Retain permitted generated output in archive/inspection independently of the
model conversation and its context resets. Make partial generations durable only through the
existing configured archive/retention policy, including permission to retain
text; this feature does not enable transcript saving. Extend text filtering to
new nested alignment/transcript payloads rather than bypassing current policy.

Building model history requires a correlated settlement/projection API. Settle
the spoken representation before its first model-history commit; never discard
or replace an already committed exchange merely to correct delivery. Preserve
the original admitted human input, internal durable tool records, model-visible
terminal results, ordering and at-most-once side effects. Late delivery corrections
remain in application projections. Compaction, transfer and recovery preserve
supported spoken text, so an unplayed suffix cannot return as shared history;
unknown delivery stays application state, not model-visible metadata.

## Missing or uncertain data

- With usable provider alignment and qualified playback progress, project the
  supported prefix. With Rime's estimates, conservatively admit a prefix under
  the validated TTS policy and record its estimate quality internally. The LLM
  receives the selected text without quality metadata.
- Without timing for an interrupted segment, retain earlier wholly delivered
  segments. Its word cutoff is unknown; do not apply a duration fraction to the
  text, assume all generated words played or treat missing evidence as zero.
  Keep the interrupted segment's generated text and unknown-delivery state in
  application records; omit unsupported text from ordinary model history.
- Without playback progress, timing alone cannot select a spoken prefix.
  Full segment settlement can retain the existing coarse delivery contract,
  with its actual evidence strength. An interrupted segment stays unresolved.
- A known zero played duration gives an empty delivered prefix. Unknown duration
  gives null/unavailable. Preserve this distinction internally and in archives;
  neither case injects playback fields or an empty fictional utterance into LLM history.
- Bad, delayed or unsupported alignment degrades only this optional evidence.
  It must not fail the call or extend the cancellation deadline. Do not generate
  substitute timings with another model or STT service implicitly.

## Implementation order and acceptance

First add the shared optional contract and fixture tests at provider boundaries;
then combine it with existing output settlement; then update transcript/archive
and conversation projections together. A participant must not start relying on
timing until all three parts work. Semantic policy can use coarse settlement
before this slice is implemented. Listening cues retain their separate output
purpose and do not become ordinary assistant exchanges through this feature.

These are internal steps in meaningful checkpoints, all tracked in the combined
milestone: A delivers ElevenLabs through transcript/archive/next-model context;
B adds Rime through the same contract; F covers combined telephone/language and
transport acceptance. Do not wait for the classifier or semantic policy to prove
spoken history, or complete a checkpoint with adapter metadata alone. The
[delivery review](voice-conversation-iterations.md) records this grouping.

Required acceptance includes the `x y z` example; zero, mid-word and exact-boundary
cutoffs; complete and queued segments; no provider timing; Rime estimates;
normalized numbers/Unicode; chunk-relative clock resets; delayed/revised/invalid
spans; generation cancelled before sentence flush; output/source replacement;
local versus remote playback evidence; late clear/mark callbacks; and distinct
recipient positions. Prove one history settlement, no duplicate response/tool
side effect, transcript-policy filtering, and consistent transfer/compaction.

Compare timestamp-derived cutoffs to recorded browser and telephone playback
for the integrated ElevenLabs and Rime profiles. Report timing error and evidence
coverage rather than assuming provider alignment is exact. Follow repository
red-green tests, root completion checks and the Lean speech-state lane when
runtime changes are made. No live acceptance is claimed by this document.

## Rejected alternatives and design review

Replacing the stored generated response loses the distinction between what the
model produced and what was delivered. Keeping full generated text as spoken
history teaches the next request that an unheard suffix was communicated.
Proportional text truncation, elapsed wall time since synthesis, and treating
cleared frames as played all invent a word boundary without adequate evidence.
Provider-specific branches inside participant policies duplicate protocol logic.

Local design review completed 2026-11-16, separately from implementation.
Identified optional capability/quality requirements, unimplemented partial-history
reconciliation, conditional archival retention, and local-playback evidence
limits. Earlier separate task lists are now superseded by the combined milestone's
A/B/F checkpoints; no scope was intentionally removed. Its review section tracks
independent coverage review separately from implementation acceptance.

The later user message-format review intentionally removes model-visible playback
metadata and delivery/correction events. Evidence collection and truthful spoken
projection remain required internally. See the [question labnote](../../labnotes/20261116-1107-message-format-questions.md)
for this clarification; earlier coverage review did not approve this amendment.
