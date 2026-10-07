# Speech integration guide

Vxpipe speech integrations implement a semantic provider contract. The contract describes
readiness, bounded input or output, transcript and turn evidence, cancellation, and lifetime.
It does not require a socket, JSON, a connected message, a provider speech-start event, or a
particular request API.

Use this guide for standalone speech-to-text or text-to-speech providers. A service that also
owns the model conversation, tools, or bidirectional agent turn lifecycle needs a separate
runtime contract rather than pretending to be independent STT and TTS.

## Choose the contract

An STT provider implements `Vxpipe.CallEngine.Speech.STTProvider`. It must accept the descriptor's
bounded audio representation and publish cumulative current-turn text. A conversational provider
must declare a real turn-boundary authority:

- `:provider_semantic` when the provider explicitly identifies the conversational turn end;
- `:provider_gap` when the provider's configured silence rule owns the turn end;
- `:local_gap` when an allocation-owned acoustic detector supplies onset and
  silence endpoints independently of recognition. This STT-only mode does not
  admit eager-end evidence or relax STS controller rules.

`:none` describes recognition without a conversational end signal and is rejected by the current
room STT admission. The conversational path also requires genuine acoustic speech-start
evidence for barge-in. External endpointing, transcript-only recognition, and manual finalization
alone are not admitted. The reviewed [local STT composition](elevenlabs-stt-session.md)
owns the detector and recognition lifetime within the allocation. A stable or committed
segment is not automatically a speaker turn. Keep segment assembly inside the provider and publish
`:turn_ended` only when the declared authority has ended the turn.

A TTS provider implements `Vxpipe.CallEngine.Speech.TTSProvider`. One engine request contains
bounded complete text. A provider may use a persistent stream, a request worker, or local
synthesis. Provider contexts, flushes, synthesis batches, and wire request IDs remain private.
The provider emits `:completed` only after every audio chunk for the engine request has received
its exact Channel credit. Sink playback and request completion are separate facts.

## Public configuration and private initialization

`configure/1` is pure and accepts only public, validated options. It returns a closed
`Speech.Descriptor` with:

- `kind`, public `settings`, and exact audio `format`;
- an honest `usage_identity` and provenance;
- `readiness`, which says whether local initialization or a provider acknowledgement is required;
- STT endpointing and optional speech-start/eager/resume evidence; or
- a deterministic 32-byte TTS `cache_identity`.

Do not read environment variables or credentials in `configure/1`. Runtime startup resolves the
credential and passes it in the provider's `:private` options. Validate it, construct the client or
connection, and avoid retaining the raw credential when a derived client is sufficient. Private
options never belong in the descriptor, call spec, logs, process labels, or `format_status/1`.

The SessionTree starts the provider under its allocation-local DynamicSupervisor. Request workers
belong under `Speech.SessionTree.commands(allocation)` through `Task.Supervisor.async_nolink/2`.
Do not create a global speech worker pool or call a provider's `start_link/1` from arbitrary code.
Owner, consumer, or allocation loss then tears down the provider and its workers through ordinary
OTP ancestry.

## Complete minimal TTS provider

The following complete module is compiled from
[`test/support/speech_guide_tts_provider.ex`](../apps/vxpipe_call_engine/test/support/speech_guide_tts_provider.ex)
and exercised by the shared conformance test. It emits one bounded PCM silence sample so it can run
without a network account. Replace that sample with provider output while preserving the descriptor,
private credential boundary, event order, one-chunk credit, cancellation, and redaction rules.

```elixir
defmodule Vxpipe.CallEngine.SpeechGuideTTSProvider do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, Playback, TTSProvider}

  @impl true
  def configure(options) do
    with {:ok, options} <- Keyword.validate(options, sample_rate: 16_000),
         sample_rate when is_integer(sample_rate) and sample_rate > 0 <-
           Keyword.fetch!(options, :sample_rate) do
      Descriptor.new(
        kind: :tts,
        settings: %{sample_rate: sample_rate},
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :guide,
          model: :minimal,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :none,
        cache_identity: :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, sample_rate}))
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options), do: TTSProvider.start_link(__MODULE__, options)

  @impl true
  def speak(pid, reference, text),
    do: GenServer.call(pid, {:speak, reference, text}, 5_000)

  @impl true
  def cancel(pid, reference, playback),
    do: GenServer.call(pid, {:cancel, reference, playback}, 5_000)

  @impl true
  def close(pid), do: GenServer.call(pid, :close, 5_000)

  @impl true
  def init(options) do
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    credential = Keyword.get(private, :credential)
    observer = Keyword.get(private, :observer)

    with true <- is_binary(credential) and byte_size(credential) > 0,
         true <- is_pid(observer),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      send(observer, {:speech_guide_client_initialized, self()})

      {:ok,
       %{
         awaiting: nil,
         channel: channel,
         last_terminal_request: nil,
         request: nil
       }}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, _text}, _from, %{request: nil} = state) do
    audio = <<0, 0>>

    with :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ),
         {:ok, credit} <- Channel.submit(state.channel, reference, audio) do
      {:reply, :ok, %{state | request: reference, awaiting: credit}}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference} = state
      ) do
    case Event.emit(state.channel, :cancelled, request_ref: reference) do
      :ok ->
        {:reply, :ok, %{state | request: nil, awaiting: nil, last_terminal_request: reference}}

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ),
      do: {:reply, :ok, %{state | last_terminal_request: nil}}

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_info(message, %{request: reference, awaiting: credit} = state) do
    case TTSProvider.credit(message, state.channel, reference, credit) do
      :ok ->
        case Event.emit(state.channel, :completed, request_ref: reference) do
          :ok ->
            {:noreply, %{state | request: nil, awaiting: nil, last_terminal_request: reference}}

          _failure ->
            {:stop, {:shutdown, :session_failed}, state}
        end

      :stale ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :guide_tts_provider)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
```

This small example performs no blocking I/O. A request-based integration should start its HTTP or
SDK work beneath `SessionTree.commands/1`, bound each response frame and total response, and
terminate the exact worker on cancellation. The tested
[`SpeechRequestTTSProfile`](../apps/vxpipe_call_engine/test/support/speech_request_tts_profile.ex)
shows streamed responses, bounded response adaptation, context-tagged cancellation, stale
completion suppression, and multiple synthesis batches. Its worker never has more than one
uncredited chunk. A batch `done` notification is adapter evidence; only the final engine request
boundary becomes `:completed`.

The tested
[`SpeechSegmentedSTTProfile`](../apps/vxpipe_call_engine/test/support/speech_segmented_stt_profile.ex)
shows replaceable partials, a stable committed segment, eager end, resume, and actual turn end as
separate observations. It deliberately supplies no upstream sequence number. Channel stamps the
local event envelope sequence; the adapter must not claim upstream deduplication that its protocol
does not provide.

## Delivery and event rules

Consumers receive one semantic event at a time and must call `Speech.Session.ack/2`. Providers call
`Speech.Event.emit/3`; they never send raw tuples to the consumer. Channel validates the event
against the descriptor and stamps allocation identity, the bound producer, and local order.

| Kind | Producer meaning | Required handling |
| --- | --- | --- |
| `:ready` | The descriptor's declared readiness evidence exists. | Emit exactly once after `Channel.bind/1`; a returned starting handle is not ready. |
| `:speech_started` | STT has declared speech-start evidence. | Emit only if advertised; consumers may use it for barge-in. |
| `:transcript` | Full current text for one `turn_ref`. | Revisions replace earlier text; stable segments remain provider-private assembly evidence. |
| `:eager_turn_ended` | Tentative end from the declared provider authority. | Emit only if advertised; it is reversible. |
| `:turn_resumed` | The eager end was withdrawn. | Emit only if advertised and retain the same `turn_ref`. |
| `:turn_ended` | The declared authority ended the conversational turn. | Include cumulative final text and matching endpointing evidence. |
| `:input_submitted` | The TTS protocol write or local synthesis start was accepted. | Correlate the exact request reference and honest usage provenance; engine admission alone is insufficient. |
| audio envelope | One bounded PCM chunk for that TTS request. | Match the exact credit with `TTSProvider.credit/4` before sending another chunk. |
| `:completed` | All request audio was credited. | Do not translate the first flush or synthesis-batch boundary into completion. |
| `:cancelled` | Exact fenced request output is locally isolated. | Kill/close its worker or context first; stale results must stay stale. |

`Session.settle_output/3` reports completed playout separately. Cancellation receives a
`Speech.Playback` snapshot after the sink has been fenced, so a provider can translate a genuine
provider interrupt offset when supported. A successful local cancel proves local output isolation;
it does not by itself prove remote billing or compute stopped.

## Bounds and errors

STT `push_audio/2` returns `:ok` only after one bounded chunk is accepted. Return
`{:error, :busy}` without accepting it when the provider's bounded slot is occupied. Do not hide an
unbounded mailbox behind an immediate `:ok`, and do not retry inside the contract.

`Speech.Session.speak/2` returns a request handle after engine admission, before provider acceptance.
The provider's `speak/3` callback returns `:ok` after it has admitted bounded provider work, while
`:input_submitted` is published only when the upstream protocol write or local synthesis start is
accepted. A clean pre-submission rejection may return `{:error, reason}` using the engine's closed
reasons such as `:busy`, `:empty_text`, `:invalid_text`, `:input_too_large`, `:output_too_large`, or
`:unsupported_character`. Channel turns that result into correlated failure evidence. Unexpected
wire, worker, credit, or protocol failure retires the allocation as `:session_failed`; it must not
silently reopen or fall back to a different provider.

Every provider operation is bounded by the engine command deadline. Channel allows one credited
TTS chunk at a time and bounded semantic events. For whole-response APIs, impose a byte limit while
reading the response, validate even-sized mono PCM16, then rechunk without copying an unbounded
queue into provider state. Streaming providers should propagate Channel credit back to the exact
wire or worker before requesting the next chunk.

`close/1` discards unfinished work. Correct cleanup comes from links, monitors, the allocation tree,
and explicit lifecycle operations. `terminate/2` is only suitable for best-effort remote cleanup.
Override `format_status/1` whenever state or messages can contain credentials, audio, transcript
text, or provider payloads.

## Speech-to-speech providers

A service that owns the model conversation, tools, and bidirectional agent turn
lifecycle implements `Vxpipe.CallEngine.Speech.STSProvider`, not `STTProvider`
plus `TTSProvider`. Composing the two independent behaviours would create two
conflicting turn authorities and fragile transcript attribution. The provider
owns its bidirectional model session, wire protocol, turn identifiers,
resumption handle, and model context. The room owns source selection, policy
and permission decisions, public turn/event IDs, transcript projection, output
sink, playback evidence, transfers, and interruption. The provider never
publishes to the room directly; all results flow through `Speech.Event.emit/3`
on the scoped channel, which stamps allocation identity, producer, and order.

Required callbacks:

| Callback | Meaning |
| --- | --- |
| `configure(public_options)` | Pure validation of model, voice, PCM formats, transcript coverage, and turn-control support. Returns `{:ok, descriptor}` with `kind: :sts` or `{:error, :invalid_configuration}`. No credentials or I/O. |
| `start_link(private_init)` | Bounded local startup under the agent capability tree via `STSProvider.start_link/2`; remote readiness is asynchronous and arrives as `:ready`. |
| `push_audio(pid, audio)` | Bounded admission of one permitted input chunk. `:ok` proves acceptance; `{:error, :busy}` means the chunk was not accepted and existing work remains valid. |
| `push_text(pid, ref, text)` | Bounded explicit text input carrying an engine-issued text reference. Before returning, the provider publishes one `:input_submitted` with that reference on protocol acceptance. Shares the single ordered input slot with audio and activity. |
| `input_activity(pid, :started \| :ended)` | Bounded, ordered external turn-control boundary through the same input slot. Unavailable in provider-controlled turn mode; the channel rejects it before provider admission. The provider must stay responsive and never call back into the channel from this callback. |
| `interrupt(pid, turn_ref)` | Promptly fence stale output for the given turn; keep the cancellation identifier until terminal isolation. |
| `send_tool_result(pid, call_ref, result)` | Deliver a bounded, authorized result to a valid provider call association. |
| `close(pid)` | Idempotent explicit shutdown; supervision guarantees cleanup. |

`configure/1` must declare the admission facts the room decides on: the
selected turn-control mode (`turn_control` is `"provider"`, `"external"`, or
`"hybrid"`) and the supported list it must belong to, input/output transcript
coverage (`input_transcript?`, `output_transcript?`), how output text settles
(`output_settlement` is `:transcript_end` or `:generation_boundary`), and
whether interrupted history can be reconciled to transport-qualified egress
evidence (`history_reconciliation?`). Provider and hybrid modes require
`endpointing: :provider_gap` or `:provider_semantic` plus speech-start evidence.
External mode requires `endpointing: :external`; its activity boundaries come
from the consumer. The supported-mode list contains only distinct members of
those three modes. STS must declare both `input_format` for microphone input
and `format` for generated output. Both use raw, mono, signed little-endian
linear16 PCM; their sample rates need not match. Google declares 16 kHz input
and 24 kHz output. Morse declares the selected rate in both directions.
An absent or invalid input format fails descriptor validation. Existing STT/TTS
descriptors keep `input_format: nil` and their original `format` meaning.
Transcript deltas alone
never open or close a turn. Source identity is stamped by the scoped channel,
so callbacks take no `source_ref`: one permitted input stream exists per STS
allocation, and a second concurrent source fails admission until a
source-handoff contract is proven.

The STS event vocabulary is readiness, input speech activity
(`:speech_started`), caller text (`:input_transcript`) versus agent text
(`:output_transcript`, each gated by the descriptor's declared coverage),
explicit text admission (`:input_submitted`, accepted once during the matching
text callback; duplicates and late submissions settle as stale), credited output
audio, input turn completion (`:turn_ended`), output generation completion
(`:output_completed`), provider interruption (`:interrupted`), and tool
call/cancellation (`:tool_call`/`:tool_cancelled`). The generic `:transcript`
event belongs to STT and is rejected for STS. Every semantic event is
acknowledged with `Speech.Session.ack/2` before room handling.

Emit output text as cumulative snapshots. When declaring `:transcript_end`, send
`Event.emit(channel, :output_transcript, turn_ref: turn, text: complete_text, final: true)`
to settle it explicitly. Earlier snapshots may omit `final` or set it to `false`;
non-boolean values are invalid. The first acknowledged final is immutable.
For `:generation_boundary`, emit the last snapshot before `:output_completed`;
that boundary freezes it, and missing text fails explicitly. The engine waits
for matching playback before publication in both modes. Explicit-final providers
have one five-second default budget after generation completion for missing text;
sink finalization and partial updates do not extend it. Timeout closes the
allocation, and interruption retires the timer and text association. Do not claim this as provider-history
reconciliation after interruption.

A `:tool_call` carries `call_ref`, `turn_ref`, `tool_name` and `arguments`.
Arguments are a JSON object with string keys, JSON values, at most 16 nesting
levels below the root and at most 65,536 encoded bytes. Invalid UTF-8, structs,
process identifiers and other non-JSON values are rejected. Names are valid
UTF-8 strings of 1–256 bytes. Arguments are excluded from event inspection.
The room still owns tool allowlisting, schema validation, active-turn checks
and execution; accepting an event does not authorize a tool.
Provider references stay private: the room creates public tool/turn IDs and uses
them consistently in execution context and start/terminal events. The room's
16-pending-call association limit rejects excess calls without evicting existing
work. Active duplicates, unknown cancellations and stale-source results cannot
create new public events. Ordered tool-envelope retirement, capability-side
bounds, supervised execution cleanup and complete schema/binding authorization
remain milestone requirements, not guarantees established by this map limit.
See the [normative STS contract](speech-provider-contract.md#sts).

### Authorizing and settling STS output

After its policy checks, the consumer calls
`{:ok, output} = Speech.Session.admit_output(session, turn_ref)`. The provider
receives `{:vxpipe_speech_output, channel, turn_ref, output_ref}`. That fresh
output reference, rather than an input-text or provider-turn reference,
authorizes `Speech.Channel.submit(channel, output_ref, pcm)`. Input admission
alone does not authorize output. STT/TTS allocations reject this operation.
Admission requires acknowledged readiness and allows one outstanding output
turn. A queued admission that exceeds the call deadline cannot later authorize
output.

The provider keeps one PCM chunk outstanding, bounded to 131,072 even bytes,
and waits for `{:vxpipe_speech_credit, channel, output_ref, credit_ref, :ok}`
before submitting another. The consumer validates the exact audio envelope
with `Session.validate_audio/2` before sink use and acknowledges bounded sink
acceptance with `Session.ack_audio/2`. Credit acknowledges acceptance, not
playback. After the final credit, the provider emits:

```elixir
Event.emit(channel, :output_completed,
  turn_ref: turn_ref,
  request_ref: output_ref
)
```

The consumer acknowledges completion, waits for actual sink settlement, then
calls `Session.settle_output(session, output, played_ms)`. The reported playback
must fit within the credited PCM duration. Completion before the final credit,
or settlement before completion acknowledgement, returns `:output_pending`.
The slot stays `:busy` until settlement. Late audio or completion from a
previous output reference returns `:stale_request`, including when the provider
turn reference is reused. This path creates no TTS usage facts; STS usage
emission remains future work.

An interruption may also terminate generation: the provider fences its
encoder and emits `:output_completed` for the fenced turn once its credit
state allows (immediately when idle, otherwise when the outstanding credit
returns). That fence-terminal marker carries no success claim; the consumer
settles it with zero egress, publishes no spoken prefix for it, and releases
the slot so the next turn can be admitted. It never revives fenced audio.

The runnable provider example is
[`SpeechSTSContractProvider`](../apps/vxpipe_call_engine/test/support/speech_sts_contract_provider.ex),
with channel-level conformance in `sts_conformance_test.exs` and
`sts_output_test.exs`. The [output admission decision](sts-output-admission.md)
records the shared lifecycle. Morse reply generation lives in
`Vxpipe.CallEngine.Provider.MorseCodeSTS.Session`, published under the
credential-free `Vxpipe.Providers.MorseCode` namespace (`STTSession`,
`TTSSession`, `STSSession`) and exercised end-to-end at the agent-owned
`Capability.SpeechToSpeech` boundary (`speech_to_speech_test.exs`,
`morse_sts_conversation_test.exs`). Generation completion alone never finishes
the public agent turn; playback and the selected transcript source must both
settle.

Room integration remains incomplete, but the microphone path is connected:
all four transcript-source combinations complete embedded PCM room calls, and
native WebRTC/telephony conversion, input delivery and readiness have focused
tests. Caller start/text/end and agent output use room-owned IDs and their exact
bound source connection. Caller publication retains late final text, bounds
unsettled associations and fences old owner-message epochs/policy intervals;
selected human STT does not create a duplicate caller pair. These checks do not
prove full native conversations, external/hybrid room control or complete
hold/transfer lifecycle acceptance. The [caller-publication decision](sts-caller-publication.md)
records that distinction. The [input-routing decision](sts-input-routing.md)
records the independent queues, directional formats and readiness contract.

### Agent-output STT

When the selected STS descriptor lacks output transcription, the agent must
select explicit `output_speech_to_text`, resolved through the existing `:stt`
provider manifest. Host enablement uses the existing `speech_to_text.providers`
settings; `output_speech_to_text` is an agent role, not a separate runtime
provider-settings section. Missing or disabled STT providers fail admission
at the selected agent-output role. The agent-owned tree feeds credited STS output audio only
(never caller microphone audio) into that second allocation, with bounded
fanout: a slow STT consumer drops chunks with a counter and can never block
sink audio. Admission requires the STT descriptor's `finite_input?: true` and
`STTProvider.finish_input/1`; unsupported selections fail before credentials or
allocation. Human conversational STT does not require this capability.
At the STS generation boundary the tree calls `finish_input/1`; `:ok` means
acceptance only. Emit all final `turn_ended` segments, then one ordered, fieldless
`input_finished` after the entire accepted finite stream is recognized. Do not
use a quiet period or an individual speech final as terminal proof. Do not accept
new audio or emit later recognition on that allocation.

The consumer aggregates finals in order (64 segment references/65,536 UTF-8 bytes
including separating spaces), ignores identical repeated finals and fails on
conflicts/overflow. Only terminal proof freezes the text; missing proof fails at
the existing deadline. It retires/replaces successful recognizers before another
reply and requires replacement readiness. The resulting text takes the single agent
transcript role after the same egress fence as provider transcripts; on
interruption the tree restarts the output STT so late text cannot leak into
the next turn, and an output STT failure settles the turn honestly without
agent text. Morse STT implements `finish_input/1` via decoder flush and terminal emission
(`stt_finish_input_test.exs`); the capability boundary is proven in
`speech_to_speech_output_stt_test.exs`, including denied policy, failure and
slow-consumer settlement. `room_authority/sts_transcript_modes_test.exs` drives
compiled embedded PCM calls across all four caller/agent transcript-source
combinations, decodes the Morse reply and checks single, correctly attributed
final transcripts after playback settlement. Google/Deepgram finite-input support
is not implemented and remains an explicit open milestone requirement; their
ordinary human STT remains available, but sidecar selection is rejected before
runtime. Native conversations and complete room lifecycle acceptance remain
separate milestone gates. See [the decision](output-recognition-settlement.md).

The capability keeps at most 16 pending reply turns while output playback or
recognizer readiness prevents admission. Readiness releases them in FIFO order;
it does not discard the remainder after admitting one turn. Exceeding that
budget fails the capability with `:pending_turn_overflow` and retires its owned
sessions. This is a turn-count limit, separate from PCM credit and the bounded
recognition-audio buffer.

Successful `Session.settle_output/3` also sends the provider
`{:vxpipe_speech_output_settled, channel, turn_ref, output_ref, played_ms}`.
Use the matching references to retire generation state. This local playback
evidence does not establish remote hearing.

### Google Gemini 3.8 Live adapter

Google connection renewal and idle connection-loss recovery use the latest
private resumption handle within the same allocation. Initial setup requests
updates; revocation or new accepted input invalidates the old checkpoint.
Handoff waits for local playback settlement and gates new input until setup is
acknowledged. It never sends old audio/history or regenerates past replies.
The default attempt budget is 5 seconds, with explicit failure and no fresh
conversation fallback. See [context restoration](sts-context-restoration.md)
for the boundary, tests and remaining hosted gate.

`Vxpipe.Providers.Google.STS` is the pure codec (model `gemini-3.8-live`,
16 kHz input / 24 kHz output PCM, provider-owned voice, both transcriptions,
configurable turn control) and `Vxpipe.Providers.Google.STSSession` is the
`STSProvider` with a private `STSSocket` under the allocation's provider
supervisor. Credentials resolve privately like the existing Google speech
sessions and never reach logs, status or tests. Fixture tests
(`providers/google/sts_test.exs`, `sts_session_test.exs`) drive a fake socket
through setup, PCM conversion, multi-part/out-of-order evidence, generation
versus playback completion, pre-audio interruption, turn-control enforcement,
tool cancellation, `goAway`/resumption/expiry and the fence-window mute for
sent-ahead bytes. The fixture wire shapes are documented in the codec module;
history reconciliation remains declared false. The Google manifest now offers
`:sts`, and configured agents select `provider: "google"`,
`model: "gemini-3.8-live"` with public voice and turn-control options. Startup
resolves the saved Google key privately and uses response-owned output.
The [Gemini acceptance milestone](milestones/gemini-live-provider-acceptance.md)
records the actual hosted and phone evidence and remaining acceptance checks;
these checks do not establish interrupted-history reconciliation.

Both pre-admission and active Google output keep at most 16 pending PCM chunks,
in addition to the channel's single outstanding audio credit. At the chunk limit,
pending audio from the same response is compacted into at most 131,072-byte
chunks without increasing the byte budget. Exhaustion still fails the session;
it does not silently drop speech or reconnect to replay it. The shared STS
capability runs sink pushes in its owned task supervisor so playback backpressure
does not block caller input or interruption; it credits audio only after delivery.
Wire decoding preserves the final partial chunk when splitting large PCM parts
at the unchanged 131,072-byte limit. Local buffer, fake-socket credit/cleanup
and PCM-tail regressions cover these guarantees (`sts_output_test.exs`,
`sts_session_test.exs`, `sts_test.exs`); they do not establish hosted capacity.

### GPT-Live duplex profile

The OpenAI provider accepts one tenant API key for both direct language models
and GPT-Live speech-to-speech. Its manifest offers `:sts`, and the call catalog
selects it. The adapter uses `gpt-live-1` for bidirectional 24 kHz PCM and
defaults the delegated Responses backend to `gpt-5`. An agent capability is
authored in the same shape as other STS providers:

```elixir
%{
  speech_to_speech: %{
    provider: "openai",
    model: "gpt-live-1",
    options: %{}
  }
}
```

Keep the API key in the tenant credential source and the agent's prompt and
allowlisted tools in its call spec; none belong in public provider options.
The adapter waits for `session.started`, forwards accepted caller audio,
segments continuous output into admitted bursts, and releases agent text only
at the local playback fence. An inferred 800 ms caller gap labels turns but
does not trigger the model's response. A mute hold preserves the model session
and pending tools. An expired or lost socket gets one replacement seeded from
bounded caller finals and heard agent text; an active answer or unanswered
caller turn prompts a brief continuation. Provider voice milliseconds and
delegated backend tokens are reported as separate usage observations.

Register an STS provider through the same closed paths as STT/TTS, plus the
provider manifest `:sts` entry in `Vxpipe.Providers`. An agent `speech_to_speech`
selection rejects any simultaneous `model_inference`/`text_to_speech`; an
agent `output_speech_to_text` selection is explicit per agent and never
inherited from human STT defaults. It resolves through the existing `:stt`
provider manifest and is required only when the selected STS descriptor lacks
output transcription.

## Production registration

Adding a module does not make untrusted call-spec input able to select it. Register a production
provider through the closed paths together:

1. Add its public provider/model/options validation and adapter mapping to
   `Vxpipe.CallEngine.CapabilityCatalog`.
2. Resolve its credential into provider-private configuration in `PlanStartup` and the owning
   `SpeechToTextRuntime` or `TextToSpeechRuntime`. Keep public descriptor options separate.
3. Add only deliberate host defaults under the owning `:vxpipe_call_engine` configuration. Runtime
   secrets remain in `config/runtime.exs` or the injected credential source.
4. Add recorded wire fixtures and tagged integration/live acceptance for the exact endpoint and
   model. Default tests must need no network account.
5. Run the shared contract against the provider and retain provider-specific tests for framing,
   authentication, upstream ordering, cancellation acknowledgement, and usage evidence.

Do not accept module names, endpoint URLs, atoms, or callback modules from call-spec input. A new
provider must be a fixed catalog entry. Do not add a public transport behaviour: wire modules are
private provider collaborators.

## Conformance commands

Run the shared provider checks from the Call Engine application while iterating:

```shell
cd apps/vxpipe_call_engine
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/speech/provider_contract_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/speech/stt_session_test.exs test/vxpipe/call_engine/speech/tts_session_test.exs
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/speech/sts_session_test.exs test/vxpipe/call_engine/speech/sts_provider_contract_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/speech/sts_conformance_test.exs test/vxpipe/call_engine/speech/sts_output_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/speech/morse_sts_conversation_test.exs test/vxpipe/call_engine/speech/sts_tool_test.exs test/vxpipe/call_engine/speech/sts_turn_control_test.exs test/vxpipe/call_engine/speech/stt_finish_input_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/capability/speech_to_speech_test.exs test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/call_spec/sts_selection_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/call_engine/plan_startup/sts_activation_test.exs --seed 0
ERL_FLAGS='+S 4:4' mix test test/vxpipe/providers/google/sts_test.exs test/vxpipe/providers/google/sts_session_test.exs --seed 0
```

Then run provider-specific unit and tagged integration tests. Before committing a production
provider, run the repository completion gates from the umbrella root:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix deps.unlock --check-unused
```

The shared harness proves Vxpipe's public contract, local lifetime, bounds, and isolation. It does
not prove a hosted service's current wire compatibility, quota, latency, voice quality, remote
cancellation, or billing behavior. Record those separately for the exact provider endpoint and
model. The [provider comparison](speech-provider-comparison.md) lists supported structural modes
and deferred contracts; it is not an integration claim.
