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
released closed subset and do not enforce `required` completeness. It is not wired
to room startup yet; existing preset behavior remains available while the milestone
proceeds through later checkpoints.

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
running after its retry budget is exhausted. This runtime is not yet the room's active
inference path.

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
