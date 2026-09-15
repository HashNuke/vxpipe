# Model-inference turn

Status: Implemented bounded vertical slice

## Decision

Vxpipe models conversational generation as a provider-neutral capability owned
by an agent participant. A room configured with the `:model_inference` agent
preset starts one model-inference capability below that room incarnation's
dynamic capability supervisor. The development adapter is ReqLLM, configured
for `google:gemini-3.5-flash-lite`.

RTVI does not select the provider, model, credential, or system prompt. Typed
RTVI input and committed speech-to-text turns both become the existing
protocol-neutral `SendText` command. Model output then follows the existing
`TextOutput`, optional text-to-speech, playout, and agent-completion path. Other
client protocols can drive the same capability without importing RTVI types
into the call engine.

## Runtime flow

```text
RTVI or another adapter       Room authority       Model capability        Provider adapter
          | SendText                 |                    |                       |
          |------------------------->| authorize + queue  |                       |
          | user turn events         |------------------->|                       |
          |<-------------------------|                    | request in Task       |
          |                          |                    |---------------------->|
          |                          |                    | normalized text/error |
          |                          | TextOutput/failure |<----------------------|
          | bot output/error         |<-------------------|                       |
          |<-------------------------|                    |                       |
```

Provider I/O runs in an application-owned, explicitly named `Task.Supervisor`.
The capability accepts work with a bounded call, and the room authority never
waits for the network request. Each room capability allows one active generation
and a bounded FIFO of pending turns. This preserves conversation order and
prevents a rapid client from creating unbounded provider work.

## Configuration and system prompt

Reusable base configuration leaves model inference disabled. An embedding OTP
application must explicitly supply the capability settings through the
`:vxpipe_call_engine` application environment. The repository development
overlay currently uses this shape:

```elixir
config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  model_inference: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.ReqLLM,
    provider_options: [
      model: "google:gemini-3.5-flash-lite",
      streaming: true,
      generation_options: [
        temperature: 0.2,
        max_tokens: 256,
        receive_timeout: 25_000,
        total_timeout: 25_000
      ]
    ],
    system_prompt: "You are a concise, helpful voice assistant...",
    maximum_context_turns: 8,
    maximum_pending_requests: 4,
    maximum_output_bytes: 65_536,
    request_timeout_ms: 30_000
  ]
```

The system prompt is trusted agent configuration. The capability snapshots it
when the room incarnation starts and places it first in every provider request.
Neither RTVI `send-text` nor the room-creation HTTP request can replace it. A
future deployment JSON loader should validate and translate its selected agent
profile into these application settings before starting the supervision tree.
A future tenant-aware resolver may choose a trusted profile per room; accepting
arbitrary browser-supplied prompts is not part of this design.

Credentials have a separate lifecycle. Inline Google selections resolve encrypted tenant
bindings through a host-injected credential source during capability preparation. Global
provider environment keys are not read. The resulting private snapshot belongs to that
activation and is excluded from prepared plans, commands, events and inspection. See
[inline provider selections](inline-provider-selections.md) for the current contract.

## Context ownership and bounds

The capability owns conversation context for exactly one room incarnation. The
system prompt is not counted against the history limit. A successful generation
adds one complete user/assistant pair; failed and timed-out turns do not enter
history. When the configured bound is exceeded, the oldest complete pair is
discarded, never one half of a turn.

The current bound is a turn count rather than a model-token budget. It gives a
simple deterministic memory ceiling but does not guarantee that every retained
turn fits a provider's context window. Token-aware compaction and durable
conversation replay remain later slices. Context is volatile: ending the room
incarnation loses it.

Because the capability belongs to the room's agent participant, its context is
room-scoped rather than connection-scoped. Multiple admitted humans in a future
shared room would contribute to the same ordered agent conversation. Private
per-participant agents require distinct capability instances or an explicit
context-routing policy.

## Provider boundary

`Vxpipe.CallEngine.Provider.ModelInference` accepts only ordered neutral
messages with `:system`, `:user`, and `:assistant` roles. Buffered generation is
the required provider contract. Streaming is optional and reports text deltas
through a backpressured callback. The capability converts those deltas into
sentence-sized segments and emits one explicit terminal signal. The ReqLLM
adapter owns these concrete concerns:

- resolving the configured provider/model identifier through ReqLLM;
- translating neutral messages to `ReqLLM.Context` messages;
- passing the runtime credential and generation options to ReqLLM;
- selecting streaming from model metadata or an explicit trusted override;
- consuming and closing a streaming response, or extracting buffered text; and
- hiding provider-specific errors from engine events and clients.

The call engine depends on ReqLLM only in this adapter. Replacing Gemini or
ReqLLM does not change room commands, capability messages, or output events.

## Failure behavior

A provider error, task exit, invalid response, or request timeout fails only the
affected turn. The capability emits `AgentTurnFailed`, does not add that turn to
history, and advances to the next queued request. The room and capability remain
available. The RTVI gateway projects that event as a generic error response
correlated with the original client message ID; provider details and credentials
are not exposed.

If the pending queue is already full, `SendText` returns the retryable
`agent_busy` engine error before participant input events are committed. Loss of
the model capability process itself still means the configured agent path is no
longer ready and existing connection failure policy applies.

## Alternatives rejected

- Calling Gemini from the gateway would couple conversational behavior to RTVI
  and duplicate it for every future client protocol.
- Calling the provider synchronously from the room authority would block room
  admission, event sequencing, and connection lifecycle work on network latency.
- Letting ReqLLM's response context become engine state would make a provider
  library's structs the call engine's internal protocol and complicate adapter
  replacement.
- Starting one concurrent request for every input would race conversation
  history and could reorder replies.
- Retaining an unbounded message list would allow the room's memory and provider
  input cost to grow for its entire lifetime.
- Supplying the system prompt from browser room creation would move trusted
  agent policy into an unauthenticated development input boundary.
- Crashing the room on an individual provider error would discard unrelated room
  and transport state for a recoverable external failure.

## Implications and deferred work

Provider token chunks never become public output directly. A bounded accumulator
emits complete sentences early and flushes the final fragment only on successful
provider completion. Every sentence is a separate sentence-aggregated
`TextOutput`, but the room keeps one logical assistant turn open across all of
them. Speech synthesis remains ordered, the gateway advances spoken progress as
each sentence starts, and only the terminal generation plus final speech playout
emits `AgentTurnCompleted`.

A provider with no streaming callback, or a ReqLLM model configured with
`streaming: false`, produces one buffered terminal segment through the identical
room and gateway path. Automatic ReqLLM selection consults model metadata;
trusted deployment configuration may override stale metadata in either
direction. Falling back after a stream has already emitted output is deliberately
rejected because it could duplicate text and bill a second request.

Token-aware context budgets, summarization, tool calls, structured output,
provider fallback, retry policy, durable context, and prompt-version identity
remain separate checkpoints. Cancellation and provider-driven spoken barge-in
operate on the same logical turn.

The development prompt requests short plain-text responses because output is
spoken. It is a configurable policy, not a hard engine rule. Output size remains
bounded defensively even when the provider ignores its token limit.

## Verification evidence

- Capability tests prove prompt placement, serialized requests, FIFO admission,
  whole-turn context eviction, timeout handling, provider failure recovery, and
  bounded pending work.
- A call-engine vertical test creates a model-inference room, attaches a human,
  completes two context-dependent turns, and observes the existing sequenced
  participant, text-output, and agent-completion events.
- A second vertical test proves a failed generation emits a retryable
  `AgentTurnFailed` event and a subsequent turn succeeds in the same room.
- Adapter tests resolve `google:gemini-3.5-flash-lite`, verify neutral-to-ReqLLM
  message translation, streaming selection, and generation options, and reject
  missing credentials or credential overrides.
- Streaming capability tests prove early sentence output, final-fragment flush,
  terminal completion, bounded aggregate output, and the one-segment buffered
  fallback. Room and gateway tests prove multiple segments retain one logical
  completion and one speaking interval.
- Gateway codec tests prove `AgentTurnFailed` becomes a correlated RTVI
  `error-response` without leaking the provider reason.
- Default tests use no network and no provider credential. Live provider quality,
  latency, billing, and model availability are operational checks rather than
  deterministic unit-test contracts.
