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
- `:provider_gap` when the provider's configured silence rule owns the turn end.

`:none` describes recognition without a conversational end signal and is rejected by the current
room STT admission. The current conversational path also requires genuine provider speech-start
evidence for barge-in. External endpointing, transcript-only recognition, and manual finalization
need a separate input-boundary owner and are not admitted by this path. A stable or committed
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
SDK work beneath `SessionTree.commands/1`, cap a whole response before adapting it, and terminate
the exact worker on cancellation. The tested
[`SpeechRequestTTSProfile`](../apps/vxpipe_call_engine/test/support/speech_request_tts_profile.ex)
shows streamed responses, bounded whole-response adaptation, context-tagged cancellation, stale
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
