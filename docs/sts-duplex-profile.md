# GPT-Live duplex profile

Status: checkpoint A profile, recorded 2026-09-25 against OpenAI's published
GPT-Live guides. This document records the verified wire facts the
[GPT-Live speech-to-speech milestone](milestones/gpt-live-speech-to-speech.md)
depends on, plus the facts that remain unverified. An unverified item is a
hosted-check task in checkpoint F, never an assumption in ordinary code.

Sources:

- [GPT-Live getting started](https://developers.openai.com/api/docs/guides/live)
- [GPT-Live WebSockets](https://developers.openai.com/api/docs/guides/voice-websockets?api=live)
- [Managing GPT-Live sessions](https://developers.openai.com/api/docs/guides/live-conversations)
- [Delegation and tools](https://developers.openai.com/api/docs/guides/live-delegation)
- [Server-side controls](https://developers.openai.com/api/docs/guides/voice-server-controls?api=live)
- [Prompting GPT-Live](https://developers.openai.com/api/docs/guides/live-prompting)
- [GPT-Live model card](https://developers.openai.com/api/docs/models/gpt-live-1)

## Connection and authentication

| Fact | Value | Evidence |
| --- | --- | --- |
| Primary WebSocket URL | `wss://api.openai.com/v1/live/sessions`, no query parameters | Documented (WebSockets guide). |
| Authentication | `Authorization: Bearer $OPENAI_API_KEY` (project API key); additional connection headers exist but are not enumerated in the prose | Documented (WebSockets guide); the exact extra headers are **unverified**. |
| Sideband URL | `wss://api.openai.com/v1/live/sessions/{session_id}/attach` | Documented (server-side controls). |
| Fork URL | `wss://api.openai.com/v1/live/sessions/{source_session_id}/fork` | Documented; forking is out of scope (`store: false`). |
| Startup ordering | Send `session.start` as the first message; wait for `session.started` before audio or commands | Documented. |
| Sideband ordering | The session is already running; never send `session.start` on an attach socket | Documented. |

The milestone uses one server-side primary WebSocket per session under the
agent capability tree. This platform does not use WebRTC, SIP, sidebands or
forks.

## `session.start` fields

`session.start` carries a `session` object. The fields the milestone sets:

| Field | Shape | Evidence |
| --- | --- | --- |
| `model` | `"gpt-live-1"` | Documented (model card). |
| `instructions` | plain string, up to 16,384 tokens | Documented (managing sessions). |
| `input` | ordered text messages: `{type: "message", role, content: [...]}`, up to 128 messages and 8,192 combined tokens | Documented (managing sessions). |
| `audio.format` | `{type: "audio/pcm", rate: 24000}` and the other formats below | Documented (WebSockets guide). |
| `audio.output.voice` | voice API name; the default is `marin` | Documented (managing sessions, voice table). |
| `delegation.type` | `"responses"` (or `"client"`); omitted/`null` selects client mode | Documented. |
| `delegation.responses` | `model` (required), `instructions`, `tools`, `tool_choice`, `parallel_tool_calls`, `max_output_tokens`, `service_tier`, `reasoning`, `text` | Documented (delegation guide). |
| `store` | boolean; defaults to `false` | Documented. This milestone sets `store: false` explicitly. |

Startup fields `model`, `instructions`, `input`, `audio` and `store` are fixed
for the session; only supported `delegation.responses` fields can change through
`session.update`. A wrong field is rejected with an `error` event carrying
`client_event_id`.

## WebSocket audio formats

One format applies to both input and output for the whole session.

| `audio.format` | Meaning |
| --- | --- |
| `{"type":"audio/pcm","rate":24000}` | mono signed 16-bit little-endian PCM at 24 kHz; the default |
| `{"type":"audio/pcm","rate":16000}` | mono signed 16-bit little-endian PCM at 16 kHz |
| `{"type":"audio/pcmu","rate":8000}` | G.711 μ-law, 8 kHz, one byte per sample |
| `{"type":"audio/pcma","rate":8000}` | G.711 A-law, 8 kHz, one byte per sample |

Audio is base64-encoded raw bytes with no container header. PCM chunks must
contain complete 16-bit samples. The adapter will prefer PCM16 at 24 kHz and
must negotiate or explicitly reject any room format it cannot convert.

**Unverified:** whether the service accepts a rate other than these four, or
whether it echoes an unsupported `audio.format` differently from the documented
`error` event. Hosted-check item.

## Input, output and transcripts

- Input audio is sent as `session.input_audio.append` with base64 `audio`; the
  event has no acknowledgment. Audio appends form one continuous ordered stream.
- Output audio arrives as `session.output_audio.delta` with base64 `delta`. On
  the primary WebSocket it has **no timing fields and no output-audio-done
  event** (documented).
- On a **sideband**, reflected `session.output_audio.delta` carries
  `start_ms`/`end_ms`; reflected input has no timestamps. This platform uses the
  primary connection, so output timing is not available from the wire.
- `session.input_transcript.delta` and `session.output_transcript.delta` each
  carry `delta`, `start_ms` and `end_ms` measured from session start. They have
  **no item ID and no completed-turn event** (documented). Delivery can be
  uneven and fragments are approximate.

## Muting and context appends

| Operation | Event | Acknowledgment |
| --- | --- | --- |
| Stop input audio, keep session and backend work | `session.input_audio.mute` | `session.input_audio.muted` |
| Resume input audio | `session.input_audio.unmute` | `session.input_audio.unmuted` |
| Trusted spoken instructions / greeting | `session.instructions.append` | `session.instructions.appended` |
| Quiet factual context, no speech requested | `session.thinking.append` | `session.thinking.appended` |
| Content the model should say, paraphrased | `session.commentary.append` | `session.commentary.appended` |

Each append takes a plain-string `content` of up to 500 tokens and a required
`delegation_id`; use `null` for session-wide context. Acknowledgment timing
reflects estimated context injection, not speech or playback. An appended
instruction can interrupt speech in progress but **does not cancel backend
work**. `input_audio.mute` does not mute model output or cancel delegated work,
which is exactly the hold semantics the milestone needs.

## Delegation and tools

- `delegation.responses` requires a backend `model` at creation. Pinned backend
  model for this milestone: a current GPT-5.6-class Responses model.
- Function calls are read from nested `response.output_item.done` items of type
  `function_call` with `call_id`, `name` and `arguments`. An
  arguments-done event alone is not sufficient.
- `response.completed` and other forwarded lifecycle events contain
  `response.output: []` even when function calls need results; read the
  individual output-item events.
- Return a result with `response.item.create` carrying
  `{type: "function_call_output", call_id, output}`; it has no separate success
  acknowledgment. Then send exactly one `response.create` when no pending calls
  remain.
- `session.delegation.created` (`target: "responses"`, `response_id`) marks a
  delegation. Client delegation is out of scope.
- Provider-hosted tools such as `web_search` are supported by the API but
  rejected by this milestone.

## Usage

- `session.usage.updated` reports cumulative voice duration in **seconds**
  (`usage.seconds`), not deltas. Convert to the milestone's `:milliseconds`
  unit.
- `session.closed` carries the final `usage`; `session.started` and
  `session.closed` both carry a session `id`.
- Backend Responses token usage appears in nested Responses completion events
  and is billed separately from voice duration.

## Close and error semantics

`session.closed.reason` is one of:

| Reason | Meaning | Milestone treatment |
| --- | --- | --- |
| `close_requested` | Application sent `session.close` or hung up | Ordinary end |
| `expired` | Session reached its duration limit | Reseed if within deadline |
| `content` | Safety filter ended the session | Fail the capability with a moderation reason |
| `remote_hangup` | Remote primary connection ended gracefully | Ordinary end |
| `connection_lost` | Primary or upstream connection lost unexpectedly | Reseed if within deadline |

- `error` events carry `error.client_event_id` identifying the failed outgoing
  command. The application must handle errors whose code is `null` or whose
  client event ID is absent.
- Moderation can end a session or cut off assistant audio for the current
  speech without ending the session; those are tracked separately from close.
- A session with no `session.closed` leaves final usage unconfirmed.
- `session.close` cancels queued Responses and rejects further commands. An
  active response can finish; one waiting for a function result cannot continue.

## Talk-over behaviour

The model is explicitly full duplex ("can listen and speak at the same time")
and the prompting guide instructs: "When the user interrupts, the assistant
should stop its answer and listen." Brief listening sounds ("backchannels") are
a separate, configurable behaviour and do not take over the caller's turn.
There is no provider event that announces a yield, so the adapter infers the
yield from output audio stopping. **Unverified:** the exact latency and
reliability of a yield under a real carrier echo, and whether an always-listening
model reacts to its own returned speech. Hosted-check items.

## Session duration limit

**Unverified.** The guides name an `expired` close reason ("the session reached
its duration limit") but publish no numeric limit or `goAway`-style warning on
the pages checked. Because no limit is documented, checkpoint E's
"renew before the documented limit" task is conditional and has no numeric
target to implement. If a limit is later documented, renewal at a quiet point
becomes required. Hosted-check item.

## Continuous output silence

**Unverified.** No page states whether `session.output_audio.delta` includes
silence between utterances. The transcript timing `start_ms`/`end_ms` is
separate from audio delivery. The adapter's energy-gate segmentation and
pre-roll are therefore the only reliable way to find burst boundaries, and must
not assume that silence is or is not present on the wire. Hosted-check item.

## Error and malformed-event handling

- Malformed JSON or an unknown top-level event type from the socket fails the
  session with an explicit reason rather than being ignored.
- A `response.failed` or `response.incomplete` discards that delegation's
  pending calls; a later result for one is not sent.
- No credential, audio or transcript may appear in logs, status or crash
  reports. Provider identifiers stay private to the adapter.

## Residual unverified items (checkpoint F hosted check)

1. Exact additional primary-connection headers beyond `Authorization`.
2. Acceptance of an `audio.format` outside the four documented forms.
3. Talk-over latency, reliability and echo behaviour on a real carrier leg.
4. Whether output audio contains continuous silence on an idle session.
5. Any numeric session duration limit.
6. Whether the default 24 kHz output can be down-converted to the room format
   without an audible seam.
