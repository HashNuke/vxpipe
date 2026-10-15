defmodule Vxpipe.Providers.ElevenLabs.STTSession do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider
  alias Vxpipe.CallEngine.Speech.{
    ActivityRuntime,
    ActivitySupervisor,
    CapabilityTree,
    Channel,
    Descriptor,
    Event,
    SessionTree,
    Silero,
    STTProvider
  }

  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeInput, ScribeSocket, ScribeTurn}
  @maximum_buffer_bytes 96_000
  @maximum_turns 4
  @timeout_ms 15_000
  # Wire-level manual commit budget: 20s of transmitted PCM at 32kB/s. The
  # provider counts every transmitted byte (idle/silence as well as voice) and
  # forces an automatic commit past ~36s of uncommitted audio (see the
  # ElevenLabs realtime transcripts/commit-strategies guide, manual 20-30s),
  # while acoustic segmentation alone only counts voiced bytes. Mirrors
  # ScribeTurn's 20s segment budget; idle commits keep the wire inside it.
  @wire_commit_bytes 20 * 32_000
  @derive {Inspect, only: [:ready?]}
  defstruct [
    :allocation,
    :channel,
    :config,
    :providers,
    :wire,
    :wire_monitor,
    :wire_module,
    :wire_options,
    :activity_options,
    :activity_tree,
    :runtime,
    :runtime_monitor,
    :model_task,
    :inference_ref,
    :accepted_audio,
    :setup_timer,
    :commit_timer,
    :commit_ref,
    :request_id,
    ready?: false,
    wire_ready?: false,
    model_ready?: false,
    stream: nil,
    input: nil,
    pending_audio: "",
    idle_buffer: "",
    wire_bytes: 0,
    idle_waiting?: false,
    turns: []
  ]

  @impl true
  defdelegate models(), to: Vxpipe.Providers.ElevenLabs.Scribe

  @impl true
  def configure(options) when is_list(options) do
    if Keyword.keyword?(options) and Keyword.get(options, :commit_strategy, :manual) == :vad do
      Vxpipe.Providers.ElevenLabs.ContinuousSTT.configure(options)
    else
      configure_manual(options)
    end
  end

  def configure(_options), do: {:error, :invalid_configuration}

  defp configure_manual(options) do
    with {:ok, public} <- Scribe.public_options(options),
         :manual <- public.commit_strategy do
      Descriptor.new(
        kind: :stt,
        settings: public,
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: 16_000,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :elevenlabs,
          model: public.model,
          provenance: :locally_measured
        },
        readiness: :provider_acknowledged,
        endpointing: :local_gap,
        speech_start?: true
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options) do
    if Keyword.fetch!(options, :descriptor).settings.commit_strategy == :vad,
      do: Vxpipe.Providers.ElevenLabs.ContinuousSTT.start_link(options),
      else: STTProvider.start_link(__MODULE__, options)
  end

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)
  @impl true
  def close(pid) do
    GenServer.call(pid, :close, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @impl true
  def init(options) do
    allocation = Keyword.fetch!(options, :allocation)
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()

    with %Scribe{commit_strategy: :manual} <- config,
         {:ok, descriptor} <-
           configure(
             Map.to_list(
               Map.take(
                 config,
                 [:model, :encoding, :sample_rate, :language_code, :commit_strategy]
               )
             )
           ),
         true <- descriptor == Keyword.fetch!(options, :descriptor),
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         allocation: allocation,
         channel: channel,
         config: config,
         providers: SessionTree.providers(allocation),
         wire_module: Keyword.get(private, :wire_module, ScribeSocket),
         wire_options: Keyword.get(private, :wire_options, []),
         activity_options: Keyword.get(private, :activity_options, []),
         stream: Silero.new(),
         input: ScribeInput.new()
       }, {:continue, :prepare}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:prepare, state) do
    generation = state.allocation.generation
    runtime = CapabilityTree.address({generation, :scribe_activity_runtime})
    tasks = CapabilityTree.address({generation, :scribe_activity_tasks})

    activity =
      Keyword.merge(state.activity_options,
        name: CapabilityTree.address({generation, :scribe_activity}),
        tasks: tasks,
        runtime: runtime,
        max_jobs: 1
      )

    options = [
      owner: self(),
      connection: Scribe.connection_options(state.config),
      commit_strategy: :manual,
      transport_options: state.wire_options
    ]

    with {:ok, tree} <-
           DynamicSupervisor.start_child(
             state.providers,
             Supervisor.child_spec({ActivitySupervisor, activity}, restart: :temporary)
           ),
         {:ok, wire} <-
           DynamicSupervisor.start_child(
             state.providers,
             %{
               id: state.wire_module,
               start: {state.wire_module, :start_link, [options]},
               restart: :temporary,
               shutdown: :brutal_kill
             }
           ) do
      load = Keyword.get(state.activity_options, :load, &Silero.ModelCache.fetch/0)

      task =
        Task.Supervisor.async_nolink(
          SessionTree.commands(state.allocation),
          fn -> prepare_model(load) end,
          shutdown: :brutal_kill
        )

      {:noreply,
       %{
         state
         | activity_tree: tree,
           runtime: runtime,
           runtime_monitor: Process.monitor(GenServer.whereis(runtime)),
           wire: wire,
           wire_monitor: Process.monitor(wire),
           model_task: task,
           setup_timer: Process.send_after(self(), :setup_timeout, @timeout_ms)
       }}
    else
      _failure -> fail(state)
    end
  end

  @impl true
  def handle_call({:push_audio, audio}, _from, %{ready?: true} = state) do
    cond do
      not Silero.valid_audio?(audio) ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}

      buffered_bytes(state) + byte_size(audio) > @maximum_buffer_bytes ->
        {:reply, {:error, :busy}, state}

      true ->
        case advance_input(%{state | pending_audio: state.pending_audio <> audio}) do
          {:ok, state} -> {:reply, :ok, state}
          _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
        end
    end
  end

  def handle_call({:push_audio, _audio}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call(:close, _from, state) do
    if state.model_task, do: Task.shutdown(state.model_task, :brutal_kill)
    if state.inference_ref, do: ActivityRuntime.cancel(state.inference_ref, state.runtime)
    if state.wire, do: DynamicSupervisor.terminate_child(state.providers, state.wire)

    if state.activity_tree,
      do: DynamicSupervisor.terminate_child(state.providers, state.activity_tree)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({ref, :ok}, %{model_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    activate(%{state | model_task: nil, model_ready?: true})
  end

  def handle_info({ref, _failure}, %{model_task: %Task{ref: ref}} = state), do: fail(state)

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {:ready, request_id}}},
        %{wire: wire, request_id: nil} = state
      ),
      do: activate(%{state | request_id: request_id})

  def handle_info(
        {:vxpipe_speech_activity, ref, {:ok, stream, probabilities}},
        %{inference_ref: ref} = state
      ) do
    with {:ok, input, actions} <-
           ScribeInput.push(state.input, state.accepted_audio, probabilities),
         {:ok, state} <-
           acoustic_actions(
             %{state | input: input, stream: stream, inference_ref: nil, accepted_audio: nil},
             actions
           ),
         {:ok, state} <- advance_recognition(state),
         {:ok, state} <- advance_input(state) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  def handle_info({:vxpipe_speech_activity, ref, _failure}, %{inference_ref: ref} = state),
    do: fail(state)

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {:partial, ""}}},
        %{wire: wire, ready?: true, turns: []} = state
      ),
      do: {:noreply, state}

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {:partial, ""}}},
        %{wire: wire, ready?: true, idle_waiting?: true} = state
      ),
      do: {:noreply, state}

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {:segment, text}}},
        %{wire: wire, ready?: true, idle_waiting?: true} = state
      )
      when text == "" do
    with {:ok, state} <- acknowledge_idle(state),
         {:ok, state} <- advance_recognition(state) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  # A provider-forced or mismatched recognized segment while an explicit idle
  # commit is outstanding must fail closed. Attaching foreign speech to an
  # unrelated acoustic turn (or silently dropping it) would confuse the later
  # explicit commit acknowledgement; the empty idle acknowledgement is the only
  # acceptable settlement for audio that carried no acoustic turn.
  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {kind, text}}},
        %{wire: wire, ready?: true, idle_waiting?: true} = state
      )
      when kind in [:partial, :segment] and text != "" do
    fail(state)
  end

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {kind, text}}},
        %{wire: wire, ready?: true, turns: [head | rest]} = state
      )
      when kind in [:partial, :segment] do
    operation = if kind == :partial, do: :partial, else: :committed

    with {:ok, turn, actions} <- apply(ScribeTurn, operation, [head.turn, text]),
         {:ok, state} <-
           recognition_actions(%{state | turns: [%{head | turn: turn} | rest]}, actions),
         {:ok, state} <- advance_recognition(state) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  def handle_info({:vxpipe_scribe_transport, wire, _event}, %{wire: wire} = state),
    do: fail(state)

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.wire_monitor or monitor == state.runtime_monitor, do: fail(state)

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{model_task: %Task{ref: ref}} = state),
    do: fail(state)

  def handle_info(:setup_timeout, %{wire_ready?: false} = state), do: fail(state)
  def handle_info({:commit_timeout, ref}, %{commit_ref: ref} = state), do: fail(state)

  def handle_info(:commit_timeout, %{commit_ref: ref} = state) when is_reference(ref),
    do: fail(state)

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :elevenlabs_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp prepare_model(load) do
    case load.() do
      {:ok, _model} -> :ok
      _failure -> :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp advance_input(%{inference_ref: ref} = state) when is_reference(ref), do: {:ok, state}
  defp advance_input(%{pending_audio: ""} = state), do: {:ok, state}

  defp advance_input(state) do
    size = min(byte_size(state.pending_audio), 32_000)
    <<audio::binary-size(size), pending::binary>> = state.pending_audio

    case ActivityRuntime.submit(state.stream, audio, state.runtime) do
      {:ok, ref} ->
        {:ok, %{state | inference_ref: ref, accepted_audio: audio, pending_audio: pending}}

      _failure ->
        {:error, :classification_failed}
    end
  end

  defp activate(%{model_ready?: true, request_id: request} = state)
       when is_binary(request) do
    result =
      if state.ready?,
        do: :ok,
        else:
          Event.emit(state.channel, :ready,
            readiness: :provider_acknowledged,
            provider_request_id: request
          )

    case result do
      result when result in [:ok, :discarded] ->
        Process.cancel_timer(state.setup_timer)

        case advance_recognition(%{state | ready?: true, wire_ready?: true, setup_timer: nil}) do
          {:ok, state} -> {:noreply, state}
          _failure -> fail(state)
        end

      _failure ->
        fail(state)
    end
  end

  defp activate(state), do: {:noreply, state}

  defp acoustic_actions(state, actions) do
    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, current} ->
      case acoustic_action(current, action) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        failure -> {:halt, failure}
      end
    end)
  end

  defp acoustic_action(state, {:speech_started, ref}) do
    if length(state.turns) < @maximum_turns do
      with result when result in [:ok, :discarded] <-
             Event.emit(state.channel, :speech_started, turn_ref: ref) do
        head = %{
          turn: ScribeTurn.new(ref),
          wire_seeded?: false,
          audio: "",
          endpoint_ms: nil,
          trailing: ""
        }

        {:ok, %{state | turns: state.turns ++ [head]}}
      end
    else
      {:error, :turn_overflow}
    end
  end

  defp acoustic_action(state, {:audio, ref, audio}) do
    update_turn(state, ref, fn head -> %{head | audio: head.audio <> audio} end)
  end

  defp acoustic_action(state, {:endpoint, ref, duration}) do
    update_turn(state, ref, fn head -> %{head | endpoint_ms: duration} end)
  end

  defp acoustic_action(state, {:idle, audio}) do
    if state.turns == [] do
      cond do
        not state.wire_ready? ->
          {:ok, %{state | idle_buffer: state.idle_buffer <> audio}}

        # While an idle commit awaits acknowledgement, queue following input
        # in order inside the existing bounded buffer instead of spending more
        # of the provider's uncommitted wire budget.
        is_reference(state.commit_ref) ->
          {:ok, %{state | idle_buffer: state.idle_buffer <> audio}}

        true ->
          send_wire_binary(state, audio)
      end
    else
      index = length(state.turns) - 1

      turns =
        List.update_at(state.turns, index, fn head ->
          Map.update(head, :trailing, audio, &(&1 <> audio))
        end)

      {:ok, %{state | turns: turns}}
    end
  end

  defp update_turn(state, ref, update) do
    turns =
      Enum.map(state.turns, fn head ->
        if head.turn.turn_ref == ref, do: update.(head), else: head
      end)

    {:ok, %{state | turns: turns}}
  end

  # Serial commit discipline: while any commit (acoustic or idle) awaits its
  # acknowledgement, withhold all further wire sends. Following input stays
  # queued in the existing bounded buffers (idle_buffer, turn audio/trailing)
  # and drains in order once the acknowledgement arrives.
  defp advance_recognition(%{commit_ref: ref} = state) when is_reference(ref),
    do: {:ok, state}

  defp advance_recognition(%{turns: []} = state) do
    if state.wire_ready? and state.idle_buffer != "" do
      case send_wire_binary(state, state.idle_buffer) do
        {:ok, state} -> {:ok, %{state | idle_buffer: ""}}
        failure -> failure
      end
    else
      {:ok, state}
    end
  end

  defp advance_recognition(%{wire_ready?: false} = state), do: {:ok, state}

  defp advance_recognition(%{turns: [%{turn: %{waiting?: true}} | _]} = state),
    do: {:ok, state}

  # Buffered pre-turn idle drains before the turn's own audio so the wire
  # preserves ordered exactly-once PCM; its bytes join the same commit epoch,
  # so they are accounted into the head turn's acoustic budget as well.
  defp advance_recognition(%{turns: [_head | _rest], idle_buffer: buffer} = state)
       when buffer != "" do
    with {:ok, state} <- send_wire_binary(state, buffer) do
      advance_recognition(%{state | idle_buffer: ""})
    end
  end

  defp advance_recognition(%{turns: [%{wire_seeded?: false} = head | rest]} = state) do
    # Onset may precede another turn's commit. Seed only when this turn owns
    # the wire, after earlier trailing/idle PCM has reached that same epoch.
    turn = ScribeTurn.new(head.turn.turn_ref, state.wire_bytes)
    head = %{head | turn: turn, wire_seeded?: true}
    advance_recognition(%{state | turns: [head | rest]})
  end

  defp advance_recognition(%{turns: [head | rest]} = state) do
    cond do
      head.audio != "" ->
        size = min(byte_size(head.audio), 32_000)
        <<audio::binary-size(size), pending::binary>> = head.audio

        with {:ok, turn, actions} <- ScribeTurn.push_audio(head.turn, audio),
             {:ok, state} <-
               recognition_actions(
                 %{state | turns: [%{head | turn: turn, audio: pending} | rest]},
                 actions
               ) do
          advance_recognition(state)
        end

      is_integer(head.endpoint_ms) ->
        with {:ok, turn, actions} <- ScribeTurn.end_turn(head.turn),
             {:ok, state} <-
               recognition_actions(%{state | turns: [%{head | turn: turn} | rest]}, actions) do
          advance_recognition(state)
        end

      true ->
        {:ok, state}
    end
  end

  defp recognition_actions(state, actions) do
    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, current} ->
      case recognition_action(current, action) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        _failure -> {:halt, {:error, :recognition_failed}}
      end
    end)
  end

  defp recognition_action(state, {:audio, audio}) do
    with :ok <- wire_call(state, :send_audio, [audio]),
         do: {:ok, %{state | wire_bytes: state.wire_bytes + byte_size(audio)}}
  end

  defp recognition_action(state, :commit) do
    with :ok <- wire_call(state, :commit, []) do
      state = clear_commit(state)
      ref = make_ref()

      {:ok,
       %{
         state
         | commit_ref: ref,
           commit_timer: Process.send_after(self(), {:commit_timeout, ref}, @timeout_ms),
           wire_bytes: 0,
           idle_waiting?: false
       }}
    end
  end

  defp recognition_action(state, {:transcript, ref, text}) do
    state = if hd(state.turns).turn.waiting?, do: state, else: clear_commit(state)

    with result when result in [:ok, :discarded] <-
           emit(state, :transcript, turn_ref: ref, text: text),
         do: {:ok, state}
  end

  defp recognition_action(%{turns: [head | rest]} = state, {:turn_ended, ref, text}) do
    trailing = Map.get(head, :trailing, "")

    with {:ok, state} <- send_wire_binary(state, trailing),
         result when result in [:ok, :discarded] <-
           emit(state, :turn_ended,
             turn_ref: ref,
             text: text,
             endpointing: :local_gap,
             audio_duration_ms: head.endpoint_ms
           ) do
      {:ok, %{clear_commit(state) | turns: rest}}
    end
  end

  defp emit(state, kind, fields),
    do:
      Event.emit(state.channel, kind, Keyword.put(fields, :provider_request_id, state.request_id))

  defp clear_commit(state) do
    if state.commit_timer, do: Process.cancel_timer(state.commit_timer)
    %{state | commit_timer: nil, commit_ref: nil}
  end

  defp buffered_bytes(state),
    do:
      Enum.reduce(
        state.turns,
        byte_size(state.input.pending) + byte_size(state.input.pre_roll) +
          byte_size(state.pending_audio) + byte_size(state.accepted_audio || "") +
          byte_size(state.idle_buffer),
        fn head, size ->
          size + byte_size(head.audio) + byte_size(head.turn.remainder) +
            byte_size(Map.get(head, :trailing, ""))
        end
      )

  defp send_wire_binary(state, ""), do: {:ok, state}

  defp send_wire_binary(state, binary) when is_binary(binary) do
    chunks = chunk_binary(binary, [])

    with {:ok, state} <-
           Enum.reduce_while(chunks, {:ok, state}, fn chunk, {:ok, current} ->
             case wire_call(current, :send_audio, [chunk]) do
               :ok ->
                 {:cont, {:ok, %{current | wire_bytes: current.wire_bytes + byte_size(chunk)}}}

               _failure ->
                 {:halt, {:error, :connection_lost}}
             end
           end) do
      maybe_request_idle_commit(state)
    end
  end

  # Issues an explicit idle commit once 20s of transmitted PCM has no acoustic
  # turn to own it. The commit carries no speech_started/transcript/turn_ended
  # semantics; its empty acknowledgement only releases the wire budget and lets
  # queued input drain in order. Same bounded 15s settlement deadline as
  # acoustic commits; a non-empty settlement fails closed elsewhere.
  defp maybe_request_idle_commit(%{turns: []} = state) do
    if state.wire_ready? and state.wire_bytes >= @wire_commit_bytes and
         not is_reference(state.commit_ref) and not state.idle_waiting? do
      with :ok <- wire_call(state, :commit, []) do
        state = clear_commit(state)
        ref = make_ref()

        {:ok,
         %{
           state
           | commit_ref: ref,
             commit_timer: Process.send_after(self(), {:commit_timeout, ref}, @timeout_ms),
             wire_bytes: 0,
             idle_waiting?: true
         }}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_request_idle_commit(state), do: {:ok, state}

  defp acknowledge_idle(%{idle_waiting?: true} = state) do
    {:ok, %{clear_commit(state) | idle_waiting?: false, wire_bytes: 0}}
  end

  defp chunk_binary("", acc), do: Enum.reverse(acc)

  defp chunk_binary(binary, acc) do
    size = min(byte_size(binary), 32_000)
    <<chunk::binary-size(size), rest::binary>> = binary
    chunk_binary(rest, [chunk | acc])
  end

  defp wire_call(state, operation, arguments) do
    apply(state.wire_module, operation, [state.wire | arguments])
  catch
    :exit, _reason -> {:error, :connection_lost}
  end

  defp fail(state), do: {:stop, {:shutdown, :session_failed}, state}
end
