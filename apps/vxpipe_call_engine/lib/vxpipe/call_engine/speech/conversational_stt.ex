defmodule Vxpipe.CallEngine.Speech.ConversationalSTT do
  @moduledoc """
  Allocation-owned human STT composition. Native recognition events are
  acknowledged before translation to one canonical turn stream. Transcript
  onset is the default; optional Silero observes the same accepted input.
  Output transcription uses the original provider directly.
  """
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Speech.{
    ActivityBoundary,
    ActivityRuntime,
    ActivitySupervisor,
    CapabilityTree,
    Channel,
    Descriptor,
    Event,
    Session,
    SessionTree,
    Silero,
    STTProvider,
    STTTurnStart
  }

  @maximum_pcm_bytes 96_000
  @chunk_bytes 32_000
  @orphan_timeout_ms 60_000

  @impl true
  def models, do: []

  @impl true
  def configure(options) do
    with true <- Keyword.keyword?(options),
         {:ok, options} <- Keyword.validate(options, [:provider, :options, vad: false]),
         provider when is_atom(provider) and provider != __MODULE__ <-
           Keyword.fetch!(options, :provider),
         true <- Code.ensure_loaded?(provider),
         vad when is_boolean(vad) <- Keyword.fetch!(options, :vad),
         {:ok, descriptor} <- provider.configure(Keyword.fetch!(options, :options)),
         :ok <- Descriptor.validate_conversational_stt(descriptor) do
      {:ok,
       %{
         descriptor
         | settings: Map.put(descriptor.settings, :vad, vad),
           finite_input?: false,
           speech_start_evidence: if(vad, do: :local_acoustic, else: :transcript)
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _error -> {:error, :invalid_configuration}
  end

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)
  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, 5_000)
  @doc false
  def push_frame(pid, frame), do: GenServer.call(pid, {:frame, frame}, 5_000)

  @impl true
  def close(pid), do: GenServer.stop(pid, :normal, 5_000)

  @impl true
  def init(options) do
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    private = Keyword.fetch!(options, :private)
    channel = Keyword.fetch!(options, :channel)
    boundary_timeout = Keyword.get(private, :boundary_timeout_ms, @orphan_timeout_ms)

    with {:ok, expected} <-
           configure(
             provider: Keyword.fetch!(private, :recognizer),
             options: Keyword.fetch!(private, :recognizer_options),
             vad: descriptor.settings.vad
           ),
         true <- expected == descriptor,
         true <- is_integer(boundary_timeout) and boundary_timeout in 1..@orphan_timeout_ms,
         :ok <- Channel.bind(channel) do
      {:ok,
       %{
         allocation: allocation,
         descriptor: descriptor,
         private: private,
         channel: channel,
         inner: nil,
         inner_monitor: nil,
         runtime: nil,
         runtime_monitor: nil,
         inference: nil,
         inference_epoch: nil,
         recognition_epoch: 0,
         pending_epoch: nil,
         pending_pcm: "",
         odd_pcm: "",
         cursor: 0,
         ready?: false,
         recognizer_ready?: false,
         detector_ready?: not descriptor.settings.vad,
         stream: nil,
         boundary: nil,
         orphan: nil,
         boundary_timeout: boundary_timeout,
         ignored_refs: MapSet.new(),
         turns: STTTurnStart.new(descriptor.settings.vad)
       }, {:continue, :prepare}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:prepare, state) do
    private = state.private

    with {:ok, tree} <-
           DynamicSupervisor.start_child(
             SessionTree.providers(state.allocation),
             {CapabilityTree, owner: self()}
           ),
         {:ok, inner, :starting} <-
           Session.start(CapabilityTree.scope(tree),
             provider: Keyword.fetch!(private, :recognizer),
             options: Keyword.fetch!(private, :recognizer_options),
             private: Keyword.get(private, :recognizer_private, []),
             start_timeout:
               max(state.allocation.deadline - System.monotonic_time(:millisecond), 1)
           ),
         {:ok, state} <-
           prepare_detector(%{state | inner: inner, inner_monitor: Process.monitor(tree)}) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  @impl true
  def handle_call(:synchronize, _from, state), do: {:reply, :ok, state}

  def handle_call({:frame, _frame}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:frame, frame}, _from, state) do
    with {:ok, pcm} <- frame_pcm(state, frame) do
      accept_input(state, frame.payload, pcm)
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:audio, _audio}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:audio, audio}, _from, state) do
    case detector_pcm(state, audio) do
      {:ok, pcm, next} ->
        case accept_input(next, audio, pcm) do
          {:reply, {:error, :busy}, _next} -> {:reply, {:error, :busy}, state}
          result -> result
        end

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  @impl true
  def handle_info({:vxpipe_speech, %Event{session: inner} = event}, %{inner: inner} = state) do
    with :ok <- Session.ack(inner, event),
         {:ok, state} <- recognition(state, event) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  def handle_info(
        {:vxpipe_speech_activity, reference, {:ok, stream, probabilities}},
        %{inference: reference, detector_ready?: false} = state
      ) do
    # Model preparation is not admitted caller audio.
    _ = {stream, probabilities}
    activate(%{state | inference: nil, detector_ready?: true, stream: Silero.new()})
  end

  def handle_info(
        {:vxpipe_speech_activity, reference, {:ok, stream, probabilities}},
        %{inference: reference} = state
      ) do
    with {:ok, state} <-
           probabilities(
             %{
               state
               | inference: nil,
                 stream:
                   if(state.inference_epoch == state.recognition_epoch,
                     do: stream,
                     else: state.stream
                   )
             },
             probabilities,
             state.inference_epoch == state.recognition_epoch
           ),
         {:ok, state} <- advance_detector(state) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  def handle_info(
        {:vxpipe_speech_activity, reference, _failure},
        %{inference: reference} = state
      ),
      do: fail(state)

  def handle_info({:orphan, token}, %{orphan: {_timer, token}} = state), do: fail(state)

  def handle_info({:DOWN, reference, :process, _pid, _reason}, state)
      when reference == state.inner_monitor or reference == state.runtime_monitor,
      do: fail(state)

  def handle_info({:vxpipe_speech_closed, inner, _reason}, %{inner: inner} = state),
    do: fail(state)

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :conversational_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp prepare_detector(%{detector_ready?: true} = state), do: {:ok, state}

  defp prepare_detector(state) do
    generation = state.allocation.generation
    runtime = CapabilityTree.address({generation, :stt_activity_runtime})

    options =
      Keyword.merge(Keyword.get(state.private, :activity_options, []),
        name: CapabilityTree.address({generation, :stt_activity}),
        tasks: CapabilityTree.address({generation, :stt_activity_tasks}),
        runtime: runtime,
        max_jobs: 1
      )

    with {:ok, _tree} <-
           DynamicSupervisor.start_child(
             SessionTree.providers(state.allocation),
             Supervisor.child_spec({ActivitySupervisor, options}, restart: :temporary)
           ),
         {:ok, reference} <-
           ActivityRuntime.submit(Silero.new(), :binary.copy(<<0>>, 1_024), runtime) do
      {:ok,
       %{
         state
         | runtime: runtime,
           runtime_monitor: Process.monitor(GenServer.whereis(runtime)),
           inference: reference,
           stream: Silero.new(),
           boundary: ActivityBoundary.new()
       }}
    end
  end

  defp recognition(state, %Event{kind: :ready}) do
    case activate(%{state | recognizer_ready?: true}) do
      {:noreply, state} -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  defp recognition(_state, %Event{kind: :failed}), do: {:error, :session_failed}

  defp recognition(state, event) do
    cond do
      MapSet.member?(state.ignored_refs, event.turn_ref) -> {:ok, state}
      not Channel.input_active?(state.channel) -> ignore_unadmitted(state, event.turn_ref)
      true -> admitted_recognition(state, event)
    end
  end

  defp ignore_unadmitted(state, reference) when is_reference(reference) do
    if MapSet.size(state.ignored_refs) < STTTurnStart.max_retired(),
      do: {:ok, %{state | ignored_refs: MapSet.put(state.ignored_refs, reference)}},
      else: {:error, :turn_overflow}
  end

  defp ignore_unadmitted(state, _reference), do: {:ok, state}

  defp admitted_recognition(state, event) do
    with {:ok, turns, emissions} <- STTTurnStart.native(state.turns, event),
         :ok <- publish(state.channel, emissions) do
      settled? = Enum.any?(emissions, fn {kind, _fields} -> kind == :turn_ended end)
      state = %{state | turns: turns}

      state =
        if settled? do
          %{
            state
            | recognition_epoch: state.recognition_epoch + 1,
              pending_pcm: "",
              pending_epoch: nil,
              stream: if(state.runtime, do: Silero.new(), else: nil),
              boundary: if(state.runtime, do: ActivityBoundary.new(), else: nil)
          }
        else
          state
        end

      {:ok, update_orphan(state, emissions)}
    end
  end

  defp activate(%{ready?: false, recognizer_ready?: true, detector_ready?: true} = state) do
    case Event.emit(state.channel, :ready, readiness: state.descriptor.readiness) do
      :ok -> {:noreply, %{state | ready?: true}}
      :discarded -> {:noreply, %{state | ready?: true}}
      _failure -> fail(state)
    end
  end

  defp activate(state), do: {:noreply, state}

  defp frame_pcm(%{runtime: nil}, _frame), do: {:ok, ""}

  defp frame_pcm(_state, frame) do
    case Vxpipe.CallEngine.Speech.STTActivityPCM.normalize(frame) do
      {:ok, pcm, _timestamp} -> {:ok, pcm}
      _failure -> {:error, :unsupported_audio}
    end
  end

  defp accept_input(state, audio, pcm) do
    if byte_size(state.pending_pcm) + byte_size(pcm) > @maximum_pcm_bytes do
      {:reply, {:error, :busy}, state}
    else
      case Session.push_audio(state.inner, audio) do
        :ok ->
          pending_epoch =
            if state.pending_pcm == "", do: state.recognition_epoch, else: state.pending_epoch

          case advance_detector(%{
                 state
                 | pending_pcm: state.pending_pcm <> pcm,
                   pending_epoch: pending_epoch
               }) do
            {:ok, next} -> {:reply, :ok, next}
            _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
          end

        {:error, :busy} ->
          {:reply, {:error, :busy}, state}

        _failure ->
          {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
      end
    end
  end

  defp detector_pcm(%{runtime: nil} = state, _audio), do: {:ok, "", state}

  defp detector_pcm(
         %{descriptor: %{format: %{encoding: :linear16, sample_rate: rate}}} = state,
         audio
       ) do
    combined = state.odd_pcm <> audio
    bytes = byte_size(combined) - rem(byte_size(combined), 2)
    <<pcm::binary-size(bytes), odd::binary>> = combined

    result =
      if pcm == "",
        do: {:ok, "", state.cursor},
        else: Vxpipe.CallEngine.Speech.STTActivityPCM.normalize_payload(pcm, state.cursor, rate)

    with {:ok, normalized, _timestamp} <- result,
         do: {:ok, normalized, %{state | cursor: state.cursor + div(bytes, 2), odd_pcm: odd}}
  end

  defp detector_pcm(_state, _audio), do: {:error, :unsupported_audio}

  defp advance_detector(%{runtime: nil} = state), do: {:ok, state}

  defp advance_detector(%{inference: reference} = state) when not is_nil(reference),
    do: {:ok, state}

  defp advance_detector(%{pending_pcm: ""} = state), do: {:ok, state}

  defp advance_detector(state) do
    bytes = min(byte_size(state.pending_pcm), @chunk_bytes)
    <<chunk::binary-size(bytes), pending::binary>> = state.pending_pcm

    with {:ok, reference} <- ActivityRuntime.submit(state.stream, chunk, state.runtime),
         do:
           {:ok,
            %{
              state
              | inference: reference,
                inference_epoch: state.pending_epoch,
                pending_pcm: pending
            }}
  end

  defp probabilities(state, _probabilities, false), do: {:ok, state}

  defp probabilities(state, probabilities, true) do
    Enum.reduce_while(probabilities, {:ok, state}, fn probability, {:ok, current} ->
      with {:ok, boundary, events} <- ActivityBoundary.push(current.boundary, probability),
           {:ok, next} <-
             acoustic(%{current | boundary: boundary}, events) do
        {:cont, {:ok, next}}
      else
        _failure -> {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp acoustic(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn
      {:speech_started, _sample}, {:ok, current} ->
        with {:ok, turns, emissions} <- STTTurnStart.activity_started(current.turns),
             :ok <- publish(current.channel, emissions) do
          {:cont, {:ok, update_orphan(%{current | turns: turns}, emissions)}}
        else
          _failure -> {:halt, {:error, :session_failed}}
        end

      {:speech_ended, _sample}, {:ok, current} ->
        {:cont, {:ok, current}}
    end)
  end

  defp update_orphan(state, emissions) do
    cond do
      is_nil(state.turns.active) ->
        if state.orphan, do: Process.cancel_timer(elem(state.orphan, 0))
        %{state | orphan: nil}

      Enum.any?(emissions, fn {kind, _} -> kind in [:speech_started, :transcript] end) ->
        if state.orphan, do: Process.cancel_timer(elem(state.orphan, 0))
        token = make_ref()
        timer = Process.send_after(self(), {:orphan, token}, state.boundary_timeout)
        %{state | orphan: {timer, token}}

      true ->
        state
    end
  end

  defp publish(channel, emissions) do
    Enum.reduce_while(emissions, :ok, fn {kind, fields}, :ok ->
      case Event.emit(channel, kind, fields) do
        result when result in [:ok, :discarded] -> {:cont, :ok}
        _failure -> {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp fail(state), do: {:stop, {:shutdown, :session_failed}, state}
end
