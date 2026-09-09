# Vxpipe Call Engine

The `vxpipe_call_engine` OTP application owns Vxpipe's protocol-neutral call
lifecycle and processing runtime.

Its first vertical slice accepts a `Vxpipe.CallEngine.Command.CreateRoom`, starts
a room incarnation through the named `Vxpipe.CallEngine.RoomSupervisor`, and
returns a `Vxpipe.CallEngine.Room.Snapshot`. The room authority is a significant,
temporary child: its termination ends that incarnation instead of independently
restarting authoritative state.

The next slice accepts `Vxpipe.CallEngine.Command.JoinParticipant` for a live
room. The room authority serializes admission and starts each temporary
participant authority through the room incarnation's named dynamic participant
supervisor. The resulting public snapshot contains domain identity and state,
not gateway sessions, WebRTC, JSON, or RTVI data.

Development rooms can also resolve a deterministic text agent. Its agent
participant uses the normal participant supervisor, while its responder runs as
a separate capability under the room's dynamic capability supervisor. Attached
connections can submit protocol-neutral `SendText` commands and receive targeted,
room-sequenced participant-turn, `TextOutput`, and `AgentTurnCompleted` events.
The engine still has no dependency on the gateway or RTVI.

The first audio slice adds one speech-to-text capability and bounded media
ingress per attached human connection. It accepts protocol-neutral Opus frames,
streams them through the Deepgram Flux adapter, and admits normalized turn and
replacement-transcription signals into the room authority. Only Flux
`EndOfTurn` commits the audio turn and dispatches its final text to the
deterministic agent. Provider I/O and raw audio remain outside the room-authority
mailbox, and the engine still contains no WebRTC or RTVI types.

The output slice adds one persistent, bounded text-to-speech capability for the
agent participant. Agent text is sent to Deepgram Flux TTS and normalized as
48 kHz mono linear16 frames delivered directly to the authorized connection's
opaque output sink. Raw audio still bypasses the room authority. Provider
completion and sink playout completion are distinct; room-sequenced agent
speaking/completion events follow sink acknowledgements.

The model-inference slice adds a provider-neutral, room-scoped conversational
capability. Development uses ReqLLM with Gemini, while the reusable base
configuration remains disabled. A trusted application-configured system prompt
is prepended to every request, successful user/assistant turns are retained with
a whole-turn bound, and provider work is serialized outside the room authority.
Generation errors fail only their correlated turn and leave the room available.
Generated text reuses the existing optional TTS and completion path.

The spoken-barge-in slice keeps provider turn detection separate from raw media
transport. An authenticated STT capability's normalized `StartOfTurn` signal
uses a protocol-neutral interrupter identity to cancel older model, synthesis,
and playout work before the participant audio turn begins. `EndOfTurn` commits
that same turn without repeating interruption. The engine runs no local VAD and
still contains no WebRTC or RTVI types.

The first definition-driven checkpoint adds a pure, engine-owned compiler for
schema `20260906.02`. Trusted hosts supply resource and tenant identity separately
from JSON-safe definition and invocation maps. The compiler validates a closed
one-human/one-agent web subset and pins capability profiles, host-tool bindings,
typed Call Variables schemas/grants/partial initial values, runtime participant
identities, and call limits into a `ResolvedCallPlan`. Variable schemas use the
released closed subset and do not enforce `required` completeness. Plan startup now
rejects valid-but-deferred features before it creates a room or provider process.

The runtime foundation now includes an application-owned Jido instance, a finite
Jido AI agent module, synchronous prompt/Action configuration before readiness, and
a serialized Vxpipe host-Action dispatcher. An engine-owned coordinator now admits
one request at a time, bounds queued turns and output, translates Jido stream/tool/
terminal events onto the existing capability contract, and excludes selected
interrupted turns from later model projections while requesting physical Jido-context
cleanup. Deterministic tests cover both a controllable runtime boundary and a real Jido
Action round. An activation supervisor
starts the dispatcher, AgentServer, and coordinator as one configured readiness unit,
restarts that set together once after an abnormal child failure, and leaves no child
running after its retry budget is exhausted. A participant supervisor now owns each
participant authority and, for an agent, that activation unit; either deliberate participant
shutdown or an exhausted activation ends the whole participant subtree without restarting
the room. Trusted hosts can now call `Vxpipe.CallEngine.start_call/2` with a compiled plan;
the initial subset starts only the entry caller and receiver, routes ordinary
turns and host Actions through the receiver's owned coordinator, and follows coordinator
restarts through a stable activation reference. Plan-selected speech combines public profile
options with application-owned secrets, transports, and bounds before startup. The repository
sample exercises this path; legacy `CreateRoom` presets remain available to embedded hosts.

The engine emits payload-free `:telemetry` events for model request/first-output timing,
TTS first provider audio, and safe model/STT/TTS provider failures. Its explicitly named
`Vxpipe.CallEngine.TelemetrySampler` periodically reports active room count, total BEAM
memory bytes, and run queue without entering a room callback. Configure the sampling cadence
under the call-engine application setting `telemetry: [sample_interval_ms: 1_000]`.
Durations use Erlang `:native` units; event names and exact observation boundaries are
documented in [the architecture](../../docs/architecture.md#security-and-observability).
Runtime request cancellation is reported as a terminal `:cancelled` model outcome with its
first-output observation preserved; it is not counted as provider unavailability.

The optional `Vxpipe.CallEngine.Diagnostics.ModelFixture` is an application-configured
development boundary for exercising the same Jido coordinator, room events, optional
TTS, gateway projection, and Telemetry paths without a hosted model request. It supports
a fixed set of success, delayed success, provider failure, and invalid no-output outcomes.
An armed outcome is consumed atomically by one request and resets to the configured
default. The fixture is disabled in base configuration; its control never appears in a
call definition, invocation, command, or RTVI message.

## Embedded telemetry consumer

An application embedding the engine can attach its own collector directly, without
starting `vxpipe_gateway`, `vxpipe_console`, Phoenix, or a database. Depend on
`:telemetry` directly in the host application and use `Vxpipe.CallEngine.Telemetry.events/0`
as the complete current engine event list:

```elixir
defmodule MyApp.VxpipeTelemetry do
  @handler_id {__MODULE__, :call_engine}

  def attach(collector) do
    :telemetry.detach(@handler_id)

    :telemetry.attach_many(
      @handler_id,
      Vxpipe.CallEngine.Telemetry.events(),
      &__MODULE__.handle_event/4,
      collector
    )
  end

  def detach, do: :telemetry.detach(@handler_id)

  def handle_event(event, measurements, metadata, collector) do
    send(collector, {:vxpipe_telemetry, event, measurements, metadata})
    :ok
  end
end
```

Attach after the host collector starts, detach during orderly shutdown, and use a stable
handler ID so startup can remove a handler left by an earlier collector. The callback runs
in the process emitting the event, so it must only perform bounded local work. The receiving
collector must bound its mailbox or apply admission before forwarding data to a network,
database, or metrics backend. Durations are in Erlang `:native` units; convert them with
`System.convert_time_unit/3`. The exact measurements, bounded metadata, and observation
boundaries are listed in [the architecture](../../docs/architecture.md#security-and-observability).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `vxpipe_call_engine` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vxpipe_call_engine, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/vxpipe_call_engine>.
