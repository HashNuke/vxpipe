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

The definition-driven compiler's current schema is `20260911.01`. It adds the normal call-wide
`media_policy` and each participant's optional `while_present` contribution. Each independently
optional policy field preserves omission as `:inherit`; explicit audio/transcript route maps are
complete direct participant-key allowlists, including meaningful empty maps and recipient arrays.
Unknown or duplicate references and malformed storage booleans fail at their exact definition path.
Compilation pins every route to runtime participant IDs so later admission and media enforcement do
not reinterpret public JSON. This checkpoint does not yet apply or intersect those policies at
runtime.

The schema also accepts validated definition-local agent transfer allowlists, derives one private default-blocking transfer binding
for each non-empty list, pins the call-level total transfer-attempt deadline, and pins each agent's
inbound `transfer_history` policy. Omission selects the privacy-safe `fresh` mode; the closed set is
`fresh`, `all_spoken`, `last_n_spoken` with a positive `turns` value, and `selected`.
Transfer-capable
activations ensure their supervised tool timeout encloses that configured budget. Destination setup
runs under a separate room-owned task supervisor, leaving Room Authority responsive while it
prepares the agent and selected TTS. Room Authority reauthorizes the source and destination at
commit, retains the source through preparation, cleans up failure/expiry, rejects late results,
then routes successful later turns through the destination and tears the source subtree down.
Room state now retains a private transcript projection of caller input accepted for processing and
assistant text acknowledged as played. Transfer preparation snapshots that projection once and
seeds `all_spoken` or the configured `last_n_spoken` window into the destination runtime after its
own prompt. `fresh` and `selected` seed no prior messages. A transfer into a `selected` destination
now requires a non-empty reason of at most 1,024 characters. The descriptor requires it only for
that destination, and the private transfer request retains it without exposing it through
inspection. Each Agent Runtime generation receives a separately bounded transient projection of
only that participant's readable Call Variables. A selected destination additionally receives the
transfer reason in that private state, not in conversation history. Re-entry preserves participant
identity with a fresh activation, and failed preparation has one bounded source-capability
restoration attempt.
Schema `20260910.06` added inbound transfer history and selected projections; schema
`20260910.04` added the transfer allowlists and generated binding. Schema `20260910.03`
added explicitly selected platform
tools to the participant's unified `tools` map. The fixed initial catalog contains
`get_current_time` and
immediate `hangup`; local aliases and conversation mode are pinned into the resolved plan without
accepting modules from definition input. Schema `20260910.02` added
an optional, closed `opening_audio` source that is pinned into the resolved call plan. A text
source carries fixed text and a file source carries an HTTPS URL without embedded credentials or a fragment;
configured values are omitted from routine struct inspection. The preceding `20260910.01`
schema added a default-blocking conversation-admission policy to every tool binding. Only an explicit
`"conversation_mode":"non_blocking"` permits later caller turns while the submitted
operation remains pending. This is independent of execution placement: every operation is
handed to an independently supervised Call Engine worker. The schema retains the pinned
client tool-visibility policy from the earlier `20260909.01` shape. Trusted
hosts supply resource and tenant identity separately
from JSON-safe definition and invocation maps. The compiler validates a closed
one-human/one-agent web subset and pins capability profiles, host-tool bindings,
typed Call Variables schemas/grants/partial initial values, runtime participant
identities, call limits, and resolved participant-local visibility overrides into
a `ResolvedCallPlan`. Variable schemas use the
released closed subset and do not enforce `required` completeness. Plan startup now
rejects valid-but-deferred features before it creates a room or provider process.

Text opening audio uses the initial receiving agent's selected TTS capability. A file opening uses
the application-configured bounded HTTPS/WAV asset pipeline and a temporary room-supervised player,
so it does not require TTS. Both forms keep caller text and audio closed until the attached output
sink confirms actual playout completion; required playback failure ends the room.

Each definition-driven room with declared Call Variables starts one authoritative
`CallVariables` process beside `RoomAuthority`. Generated `read_variables`,
`update_variables`, and `update_variable` Actions call that owner directly with
engine-bound identity, section grants, revisions, schema checks, deadlines, and size bounds.
Readable values are refreshed into each model round without becoming conversation history;
accepted updates emit an exact private archival handoff but do not claim database durability.
Public tool events are hidden by default and are filtered to configured metadata or full
detail at the gateway before delivery. The trusted Console sample selects full visibility and
prefills a synthetic read-only order so this path can be exercised on the shared Phoenix port.

Definition-driven agent participants run through the standalone `Vxpipe.AgentRuntime`; the Call
Engine no longer starts or depends on Jido. Each activation owns one request supervisor,
coordinator, `Tool.InvocationSupervisor`, invocation registry, and Agent Runtime Session under one
bounded one-for-all restart budget. A participant supervisor owns that activation unit, so
participant shutdown or an exhausted activation restart ends that participant subtree without
restarting the room.

Every model-requested host or Call Variables operation is submitted to a bounded temporary worker
under the active agent. `Tool.Invocation` owns one attempt, result bound, and deadline. The
authoritative registry retains accepted work through leased and explicitly consumed completion,
exposes only payload-free pending status, reconciles identical invocation IDs, and bounds active
capacity plus consumed-ID tombstones. No action executes inline in the Session, model request task,
or coordinator.

An omitted tool-binding conversation mode is blocking; explicit `non_blocking` permits later caller
turns while the same supervised worker runs. A blocking invocation finishes the current
acknowledgement round, then later caller input receives a deterministic hold without entering the
model. Non-blocking turns include the committed running acknowledgement and current safe pending
projection. Terminal outcomes enter the Session once as private engine-origin continuations.
Caller interruption stops stale speech/model output but does not cancel accepted tool workers;
participant/room shutdown terminates their local execution subtree.

Resolved platform tools use that same descriptor and invocation boundary, but their canonical
implementations come only from a closed Call Engine catalog. `hangup` returns a typed effect from
its worker; the invocation registry publishes ordered tool-start/completion facts before Room
Authority applies the effect and terminates the room. It never ends the call inline inside the
agent/runtime process or before the tool lifecycle can be archived.

The optional legacy `CreateRoom` model-inference preset remains available to embedded hosts only as
a text-generation compatibility path. It advertises no tools and rejects an unsolicited provider
tool response as invalid without executing it or projecting a tool lifecycle. Tool-enabled calls
use a compiled definition and Agent Runtime.

Terminal tool results are now leased before caller work and submitted through the Session's private
engine-origin continuation API. Successful committed continuation acknowledges and removes the
registry record; a failed uncommitted continuation releases it and stops the coordinator rather than
rerunning the tool or admitting caller work with missing state. The active-request and terminal-
outcome mechanics live in separate cohesive modules so the coordinator remains the scheduler rather
than becoming another all-purpose runtime.

The engine emits payload-free `:telemetry` events for model request/first-output timing,
TTS first provider audio, safe model/STT/TTS provider failures, and background-tool admission,
terminal duration, completion handoff, and bounded worker/mailbox pressure. Its explicitly named
`Vxpipe.CallEngine.TelemetrySampler` periodically reports active room count, total BEAM
memory bytes, and run queue without entering a room callback. Configure the sampling cadence
under the call-engine application setting `telemetry: [sample_interval_ms: 1_000]`.
Durations use Erlang `:native` units; event names and exact observation boundaries are
documented in [the architecture](../../docs/architecture.md#security-and-observability).
Runtime request cancellation is reported as a terminal `:cancelled` model outcome with its
first-output observation preserved; it is not counted as provider unavailability.

The optional `Vxpipe.CallEngine.Diagnostics.ModelFixture` is an application-configured
development boundary for exercising the same Agent Runtime coordinator, room events, optional
TTS, gateway projection, and Telemetry paths without a hosted model request. It supports
a fixed set of success, delayed success, provider failure, and invalid no-output outcomes.
An armed outcome is consumed atomically by one request and resets to the configured
default. The fixture is disabled in base configuration; its control never appears in a
call definition, invocation, command, or RTVI message.

## Local Morse audio providers

`Vxpipe.CallEngine.Provider.MorseCodeSTT` and `MorseCodeTTS` are opt-in, in-process
implementations of the ordinary speech capability contracts. They encode and decode controlled
International Morse tones; they do not recognize spoken language, run VAD, or use a hosted API.
The application must register each implementation under the relevant speech setting's closed
`:providers` map, and a trusted capability profile must select the same module. Existing
top-level STT/TTS settings remain the legacy/default implementations.

The direct signal format is signed 16-bit little-endian mono PCM. Supported sample rates are
8, 16, 24, and 48 kHz. Defaults are 16 kHz, a 700 Hz tone, amplitude 4,096, a 60 ms dot unit,
a 10 ms analysis window, 100 Hz frequency tolerance, and detection threshold 300. Dashes are
three units; gaps within a character, between characters, and between words are 1, 3, and 7
units. A local 14-unit trailing gap completes an utterance. Decoder timing accepts one analysis
window of tolerance. Default bounds are 256 UTF-8 input bytes, 8,388,608 generated/accepted
audio bytes, and 60 seconds per undecided utterance; invalid configuration, unsupported text,
wrong-frequency/malformed signals, and bound violations fail explicitly.

Text is uppercased, leading/trailing whitespace is removed, and runs of whitespace become one
word gap. The supported alphabet is `A-Z`, `0-9`, and `. , : ? ' - / ( ) " = + @`. No other
character is transliterated or silently removed. TTS emits acknowledged 20 ms frames at real
time by default and holds only one unacknowledged frame. Interruption discards the remaining
encoder generation. STT preserves state across arbitrary binary chunks, including a split PCM
sample, and emits a final turn only after its trailing gap or an explicit valid flush.

The deterministic integration proof is:

```shell
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
```

That test compiles a real call plan, injects independently chunked linear16 `SOS`, observes an
attributed transcript, runs a local model response, collects real TTS output, and independently
decodes it. It requires no speech credential or network access. Browser microphone audio is
currently Opus and is outside this decoder's direct-PCM contract; no lossy-codec, acoustic echo,
ordinary microphone, or general noise-robustness claim is made. The Console's opt-in `morse`
development profile therefore uses typed input and 48 kHz Morse TTS only.

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
