defmodule Vxpipe.CallEngine.Capability.TextToSpeech do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @call_timeout 5_000
  @maximum_text_bytes 65_536

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

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
           current: nil,
           maximum_requests: Keyword.get(options, :maximum_requests, 4),
           media_format: provider_module.media_format(provider_config),
           owner: owner,
           pending: :queue.new(),
           provider_module: provider_module,
           transport: transport,
           transport_module: transport_module
         }}

      {:error, _reason} ->
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

  @impl true
  def handle_info(
        {:vxpipe_tts_transport, transport, {:control, payload}},
        %{transport: transport} = state
      ) do
    case state.provider_module.decode(payload) do
      {:ok, %Signal{} = signal} -> handle_signal(signal, state)
      {:ignore, _reason} -> {:noreply, state}
      {:error, _reason} -> stop_unavailable(:invalid_provider_message, state)
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, transport, {:audio, reference, payload}},
        %{transport: transport} = state
      )
      when is_reference(reference) do
    case process_audio(payload, state) do
      {:ok, state} ->
        send(transport, {:vxpipe_tts_audio_result, self(), reference, :ok})
        {:noreply, state}

      {:error, reason, state} ->
        send(transport, {:vxpipe_tts_audio_result, self(), reference, {:error, reason}})
        stop_unavailable(reason, state)
    end
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
        {:vxpipe_audio_playback, sink, turn, status},
        %{current: %{request: request}} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             status in [:started, :completed] do
    send(state.owner, {:vxpipe_tts_playback, self(), request, status})

    if status == :completed do
      case start_next(%{state | current: nil}) do
        {:ok, state} -> {:noreply, state}
        {:error, state} -> stop_unavailable(:transport_closed, state)
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:EXIT, transport, _reason}, %{transport: transport} = state) do
    stop_unavailable(:transport_closed, state)
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = safe_close(state.transport_module, state.transport)
    :ok
  end

  defp handle_signal(%Signal{kind: :speech_started, provider_speech_id: speech_id}, state) do
    case state.current do
      %{phase: :awaiting_start} = current ->
        {:noreply, %{state | current: %{current | phase: :streaming, speech_id: speech_id}}}

      _other ->
        stop_unavailable(:invalid_provider_state, state)
    end
  end

  defp handle_signal(%Signal{kind: :speech_completed, provider_speech_id: speech_id}, state) do
    case state.current do
      %{phase: phase, request: request, speech_id: ^speech_id} = current
      when phase in [:streaming, :awaiting_start] ->
        case OutputSink.finish(request.output_sink, request.correlation_id, self()) do
          :ok -> {:noreply, %{state | current: %{current | phase: :draining}}}
          {:error, _reason} -> stop_unavailable(:audio_output_failed, state)
        end

      _other ->
        stop_unavailable(:invalid_provider_state, state)
    end
  end

  defp handle_signal(%Signal{kind: :failed}, state), do: stop_unavailable(:provider_failed, state)
  defp handle_signal(%Signal{kind: :warning}, state), do: {:noreply, state}
  defp handle_signal(%Signal{kind: _other}, state), do: {:noreply, state}

  defp start_request(request, state) do
    speak = state.provider_module.encode_speak(request.text)
    flush = state.provider_module.encode_flush()

    with :ok <- safe_send_control(state.transport_module, state.transport, speak),
         :ok <- safe_send_control(state.transport_module, state.transport, flush) do
      {:ok, %{state | current: %{phase: :awaiting_start, request: request, speech_id: nil}}}
    else
      {:error, _reason} -> {:error, state}
    end
  end

  defp process_audio(payload, state) do
    with %{phase: :streaming, request: request} <- state.current,
         {:audio, audio} <- state.provider_module.decode_audio(payload),
         :ok <- OutputSink.push(request.output_sink, output_frame(request, audio, state)) do
      {:ok, state}
    else
      _invalid_or_unavailable -> {:error, :audio_output_failed, state}
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
    send(state.owner, {:vxpipe_tts_unavailable, self(), reason})
    {:stop, reason, state}
  end

  defp stop_unavailable(reason, reply, state) do
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
end
