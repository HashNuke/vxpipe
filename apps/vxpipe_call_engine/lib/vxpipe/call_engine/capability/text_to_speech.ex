defmodule Vxpipe.CallEngine.Capability.TextToSpeech do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Capability.TextToSpeech.Usage
  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal
  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @call_timeout 5_000
  @maximum_text_bytes 65_536

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :participant_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec synthesize(pid(), TextToSpeechRequest.t()) ::
          :ok | {:error, :invalid_request | :queue_full | :unavailable}
  def synthesize(capability, %TextToSpeechRequest{} = request) do
    GenServer.call(capability, {:synthesize, request}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(pid()) ::
          {:ok, [{TextToSpeechRequest.t(), non_neg_integer()}]} | {:error, :unavailable}
  def interrupt(capability) when is_pid(capability) do
    GenServer.call(capability, :interrupt, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(options, :owner)
    {provider_module, provider_config} = Keyword.fetch!(options, :provider)
    {transport_module, transport_options} = Keyword.fetch!(options, :transport)

    case transport_module.start_link(
           owner: self(),
           connection: provider_module.connection_options(provider_config),
           transport_options: transport_options
         ) do
      {:ok, transport} ->
        {:ok,
         %{
           audio_output: nil,
           current: nil,
           maximum_requests: Keyword.get(options, :maximum_requests, 4),
           media_format: provider_module.media_format(provider_config),
           owner: owner,
           pending: :queue.new(),
           playback_offset_ms: 0,
           provider_module: provider_module,
           task_supervisor: Keyword.fetch!(options, :task_supervisor),
           transport: transport,
           transport_module: transport_module,
           usage_context: Keyword.get(options, :usage)
         }}

      {:error, _reason} ->
        Telemetry.provider_failure(:tts, provider_module, :transport_closed)
        {:stop, :transport_start_failed}
    end
  end

  @impl true
  def handle_call({:synthesize, request}, _from, state) do
    cond do
      not valid_request?(request) ->
        {:reply, {:error, :invalid_request}, state}

      state.current == nil ->
        case start_request(request, state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, state} -> stop_unavailable(:transport_closed, {:error, :unavailable}, state)
        end

      :queue.len(state.pending) >= state.maximum_requests ->
        {:reply, {:error, :queue_full}, state}

      true ->
        {:reply, :ok, %{state | pending: :queue.in(request, state.pending)}}
    end
  end

  def handle_call(:interrupt, _from, %{current: nil} = state) do
    interrupted = Enum.map(:queue.to_list(state.pending), &{&1, 0})
    {:reply, {:ok, interrupted}, %{state | pending: :queue.new()}}
  end

  def handle_call(:interrupt, _from, %{current: %{phase: phase}} = state)
      when phase in [:discarding, :interrupting] do
    interrupted = Enum.map(:queue.to_list(state.pending), &{&1, 0})
    {:reply, {:ok, interrupted}, %{state | pending: :queue.new()}}
  end

  def handle_call(:interrupt, _from, state) do
    current = state.current
    pending = Enum.map(:queue.to_list(state.pending), &{&1, 0})

    {played_ms, state} = interrupt_output(current, state)
    state = %{state | pending: :queue.new()}

    case interrupt_provider(current, played_ms, state) do
      {:ok, state} -> {:reply, {:ok, [{current.request, played_ms} | pending]}, state}
      {:error, state} -> stop_unavailable(:transport_closed, {:error, :unavailable}, state)
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_tts_transport, transport, {:control, payload}},
        %{transport: transport} = state
      ) do
    case state.provider_module.decode(payload) do
      {:ok, %Signal{} = signal} ->
        state = %{state | current: Usage.observe_signal(state.current, signal)}
        handle_signal(signal, state)

      {:ignore, _reason} ->
        {:noreply, state}

      {:error, _reason} ->
        stop_unavailable(:invalid_provider_message, state)
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, transport, {:audio, reference, payload}},
        %{transport: transport, audio_output: nil} = state
      )
      when is_reference(reference) do
    case prepare_audio(payload, state) do
      {:push, request, audio, state} ->
        state = start_audio_output(request, audio, reference, state)
        {:noreply, state}

      {:drop, state} ->
        send(transport, {:vxpipe_tts_audio_result, self(), reference, :ok})
        {:noreply, state}

      {:error, reason} ->
        send(transport, {:vxpipe_tts_audio_result, self(), reference, {:error, reason}})
        stop_unavailable(reason, state)
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, transport, {:audio, reference, _payload}},
        %{transport: transport} = state
      )
      when is_reference(reference) do
    send(transport, {:vxpipe_tts_audio_result, self(), reference, {:error, :audio_output_busy}})
    stop_unavailable(:audio_output_busy, state)
  end

  def handle_info(
        {:vxpipe_tts_transport, transport, {:audio, payload}},
        %{transport: transport} = state
      ) do
    case process_audio(payload, state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason, state} -> stop_unavailable(reason, state)
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, transport, {:closed, _reason}},
        %{transport: transport} = state
      ) do
    stop_unavailable(:transport_closed, state)
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, :started},
        %{current: %{phase: phase, request: request}} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             phase not in [:discarding, :interrupting] do
    send(state.owner, {:vxpipe_tts_playback, self(), request, :started})
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, {:completed, total_ms}},
        %{current: %{phase: :draining, request: request}} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             is_integer(total_ms) and total_ms >= 0 do
    send(state.owner, {:vxpipe_tts_playback, self(), request, :completed})
    state = %{state | current: nil, playback_offset_ms: state.playback_offset_ms + total_ms}

    case start_next(state) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> stop_unavailable(:transport_closed, state)
    end
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, {:progress, played_ms, total_ms} = progress},
        %{current: %{phase: phase, request: request} = current} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms and phase not in [:discarding, :interrupting] do
    send(state.owner, {:vxpipe_tts_playback, self(), request, progress})
    {:noreply, %{state | current: Map.put(current, :played_ms, played_ms)}}
  end

  def handle_info(
        {reference, result},
        %{audio_output: %{task: %{ref: reference}} = output} = state
      ) do
    Process.demonitor(reference, [:flush])
    state = %{state | audio_output: nil}

    cond do
      result == :ok ->
        acknowledge_audio_output(output, :ok)
        {:noreply, state}

      result == {:error, :interrupted} and state.current != nil and
          state.current.phase in [:discarding, :interrupting] ->
        acknowledge_audio_output(output, :ok)
        {:noreply, state}

      true ->
        acknowledge_audio_output(output, {:error, :audio_output_failed})
        stop_unavailable(:audio_output_failed, state)
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{audio_output: %{task: %{ref: monitor}} = output} = state
      ) do
    acknowledge_audio_output(output, {:error, :audio_output_failed})
    stop_unavailable(:audio_output_failed, %{state | audio_output: nil})
  end

  def handle_info({:EXIT, transport, _reason}, %{transport: transport} = state) do
    stop_unavailable(:transport_closed, state)
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_audio_output(state.audio_output)
    _ = safe_close(state.transport_module, state.transport)
    :ok
  end

  defp handle_signal(%Signal{kind: :speech_started, provider_speech_id: speech_id}, state) do
    case state.current do
      %{phase: :awaiting_start} = current ->
        {:noreply, %{state | current: %{current | phase: :streaming, speech_id: speech_id}}}

      %{phase: :discarding} = current ->
        {:noreply, %{state | current: %{current | speech_id: speech_id}}}

      _other ->
        stop_unavailable(:invalid_provider_state, state)
    end
  end

  defp handle_signal(%Signal{kind: :speech_completed, provider_speech_id: speech_id}, state) do
    case state.current do
      %{phase: phase, request: request, speech_id: ^speech_id}
      when phase in [:streaming, :awaiting_start] ->
        case OutputSink.finish(request.output_sink, request.correlation_id, self()) do
          :ok ->
            state = finish_usage(:succeeded, state)
            {:noreply, %{state | current: %{state.current | phase: :draining}}}

          {:error, _reason} ->
            stop_unavailable(:audio_output_failed, state)
        end

      %{phase: phase, speech_id: ^speech_id}
      when phase in [:discarding, :interrupting] ->
        finish_interruption(state.playback_offset_ms, finish_usage(:cancelled, state))

      _other ->
        stop_unavailable(:invalid_provider_state, state)
    end
  end

  defp handle_signal(
         %Signal{
           kind: :speech_interrupted,
           provider_speech_id: speech_id,
           audio_played_ms: audio_played_ms
         },
         state
       ) do
    case state.current do
      %{phase: :interrupting, speech_id: ^speech_id} ->
        state = finish_usage(:cancelled, state)
        finish_interruption(max(audio_played_ms, state.playback_offset_ms), state)

      _other ->
        stop_unavailable(:invalid_provider_state, state)
    end
  end

  defp handle_signal(%Signal{kind: :failed}, state), do: stop_unavailable(:provider_failed, state)
  defp handle_signal(%Signal{kind: :warning}, state), do: {:noreply, state}
  defp handle_signal(%Signal{kind: _other}, state), do: {:noreply, state}

  defp start_request(request, state) do
    started_at = Telemetry.started_at()
    speak = state.provider_module.encode_speak(request.text)
    flush = state.provider_module.encode_flush()

    case safe_send_control(state.transport_module, state.transport, speak) do
      :ok ->
        state = %{
          state
          | current: %{
              phase: :awaiting_start,
              played_ms: 0,
              request: request,
              speech_id: nil,
              started_at: started_at,
              first_audio_observed?: false,
              usage: Usage.start(request, state.usage_context, state.media_format)
            }
        }

        case safe_send_control(state.transport_module, state.transport, flush) do
          :ok -> {:ok, state}
          {:error, _reason} -> {:error, state}
        end

      {:error, _reason} ->
        {:error, state}
    end
  end

  defp process_audio(payload, state) do
    case prepare_audio(payload, state) do
      {:push, request, audio, state} ->
        state = observe_first_audio(state)

        case OutputSink.push(request.output_sink, output_frame(request, audio, state)) do
          :ok -> {:ok, state}
          {:error, _reason} -> {:error, :audio_output_failed, state}
        end

      {:drop, state} ->
        {:ok, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp prepare_audio(payload, state) do
    case state.current do
      %{phase: :streaming, request: request} ->
        case state.provider_module.decode_audio(payload) do
          {:audio, audio} ->
            state = %{state | current: Usage.observe_audio(state.current, audio)}
            {:push, request, audio, state}

          {:error, _reason} ->
            {:error, :audio_output_failed}
        end

      %{phase: phase} when phase in [:discarding, :interrupting] ->
        case state.provider_module.decode_audio(payload) do
          {:audio, audio} ->
            state = %{state | current: Usage.observe_audio(state.current, audio)}
            {:drop, state}

          {:error, _reason} ->
            {:error, :audio_output_failed}
        end

      _other ->
        {:error, :audio_output_failed}
    end
  end

  defp start_audio_output(request, audio, transport_reference, state) do
    state = observe_first_audio(state)
    frame = output_frame(request, audio, state)

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        OutputSink.push(request.output_sink, frame)
      end)

    audio_output = %{
      task: task,
      transport: state.transport,
      transport_reference: transport_reference
    }

    %{state | audio_output: audio_output}
  end

  defp interrupt_output(current, state) do
    result =
      OutputSink.interrupt(
        current.request.output_sink,
        current.request.correlation_id,
        self()
      )

    case result do
      {:ok, played_ms} ->
        {played_ms, state}

      {:error, :wrong_turn} when state.audio_output != nil ->
        stop_audio_output(state.audio_output)
        acknowledge_audio_output(state.audio_output, :ok)
        {0, %{state | audio_output: nil}}

      {:error, _reason} ->
        {0, state}
    end
  end

  defp acknowledge_audio_output(output, result) do
    send(
      output.transport,
      {:vxpipe_tts_audio_result, self(), output.transport_reference, result}
    )
  end

  defp stop_audio_output(nil), do: :ok

  defp stop_audio_output(output) do
    Process.demonitor(output.task.ref, [:flush])
    _ = Task.shutdown(output.task, :brutal_kill)
    :ok
  end

  defp interrupt_provider(%{phase: :draining}, played_ms, state) do
    {:ok, %{state | current: nil, playback_offset_ms: state.playback_offset_ms + played_ms}}
  end

  defp interrupt_provider(%{phase: :streaming} = current, played_ms, state)
       when played_ms > 0 do
    playback_offset_ms = state.playback_offset_ms + played_ms
    interrupt = state.provider_module.encode_interrupt(playback_offset_ms)

    case safe_send_control(state.transport_module, state.transport, interrupt) do
      :ok ->
        {:ok,
         %{
           state
           | current: %{current | phase: :interrupting},
             playback_offset_ms: playback_offset_ms
         }}

      {:error, _reason} ->
        {:error, state}
    end
  end

  defp interrupt_provider(current, played_ms, state) do
    {:ok,
     %{
       state
       | current: %{current | phase: :discarding},
         playback_offset_ms: state.playback_offset_ms + played_ms
     }}
  end

  defp finish_interruption(playback_offset_ms, state) do
    state = %{state | current: nil, playback_offset_ms: playback_offset_ms}

    case start_next(state) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> stop_unavailable(:transport_closed, state)
    end
  end

  defp start_next(state) do
    case :queue.out(state.pending) do
      {{:value, request}, pending} ->
        start_request(request, %{state | pending: pending})

      {:empty, _pending} ->
        {:ok, state}
    end
  end

  defp output_frame(request, audio, state) do
    struct!(AudioOutputFrame, %{
      tenant_id: request.tenant_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      codec: state.media_format.codec,
      sample_rate: state.media_format.sample_rate,
      channels: state.media_format.channels,
      byte_order: state.media_format.byte_order,
      payload: audio,
      reply_to: self()
    })
  end

  defp valid_request?(request) do
    Enum.all?(
      [
        request.tenant_id,
        request.room_id,
        request.incarnation_id,
        request.participant_id,
        request.source_participant_id,
        request.connection_id,
        request.command_id,
        request.correlation_id
      ],
      &(is_binary(&1) and byte_size(&1) > 0)
    ) and is_binary(request.text) and byte_size(request.text) > 0 and
      byte_size(request.text) <= @maximum_text_bytes and is_pid(request.output_sink)
  end

  defp stop_unavailable(reason, state) do
    state = finish_usage(:failed, state)
    Telemetry.provider_failure(:tts, state.provider_module, reason)
    send(state.owner, {:vxpipe_tts_unavailable, self(), reason})
    {:stop, reason, state}
  end

  defp stop_unavailable(reason, reply, state) do
    state = finish_usage(:failed, state)
    Telemetry.provider_failure(:tts, state.provider_module, reason)
    send(state.owner, {:vxpipe_tts_unavailable, self(), reason})
    {:stop, reason, reply, state}
  end

  defp safe_send_control(module, transport, payload) do
    try do
      module.send_control(transport, payload)
    catch
      :exit, _reason -> {:error, :transport_closed}
    end
  end

  defp safe_close(module, transport) do
    try do
      module.close(transport)
    catch
      :exit, _reason -> :ok
    end
  end

  defp observe_first_audio(%{current: %{first_audio_observed?: false} = current} = state) do
    Telemetry.tts_first_audio(current.started_at, state.provider_module)
    %{state | current: %{current | first_audio_observed?: true}}
  end

  defp observe_first_audio(state), do: state

  defp finish_usage(outcome, state) do
    %{state | current: Usage.finish(state.current, outcome, state.owner)}
  end
end
