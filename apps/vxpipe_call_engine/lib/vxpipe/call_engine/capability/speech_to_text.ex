defmodule Vxpipe.CallEngine.Capability.SpeechToText do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  @call_timeout 5_000
  @maximum_audio_bytes 131_072

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec push_audio(pid(), AudioFrame.t()) :: :ok | {:error, :unsupported_audio | :unavailable}
  def push_audio(capability, %AudioFrame{} = frame) do
    GenServer.call(capability, {:push_audio, frame}, @call_timeout)
  end

  @spec deliver_audio(pid(), pid(), reference(), AudioFrame.t()) :: :ok
  def deliver_audio(capability, ingress, reference, %AudioFrame{} = frame)
      when is_pid(ingress) and is_reference(reference) do
    send(capability, {:vxpipe_stt_audio, ingress, reference, frame})
    :ok
  end

  @spec fail(pid(), :media_overloaded) :: :ok
  def fail(capability, reason) when reason in [:media_overloaded] do
    GenServer.cast(capability, {:fail, reason})
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    identity = %{
      tenant_id: Keyword.fetch!(options, :tenant_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      connection_id: Keyword.fetch!(options, :connection_id)
    }

    owner = Keyword.fetch!(options, :owner)
    {provider_module, provider_config} = Keyword.fetch!(options, :provider)
    {transport_module, transport_options} = Keyword.fetch!(options, :transport)
    connection = provider_module.connection_options(provider_config)

    case transport_module.start_link(
           owner: self(),
           connection: connection,
           transport_options: transport_options
         ) do
      {:ok, transport} ->
        {:ok,
         %{
           identity: identity,
           last_provider_sequence: -1,
           media_format: provider_module.media_format(provider_config),
           owner: owner,
           provider_module: provider_module,
           transport: transport,
           transport_module: transport_module
         }}

      {:error, _reason} ->
        {:stop, :transport_start_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, frame}, _from, state) do
    if supported_audio?(frame, state) do
      result = safe_send_audio(state.transport_module, state.transport, frame.payload)
      reply = if result == :ok, do: :ok, else: {:error, :unavailable}
      {:reply, reply, state}
    else
      {:reply, {:error, :unsupported_audio}, state}
    end
  end

  @impl true
  def handle_cast({:fail, reason}, state) do
    stop_unavailable(reason, state)
  end

  @impl true
  def handle_info({:vxpipe_stt_audio, ingress, reference, frame}, state)
      when is_pid(ingress) and is_reference(reference) do
    if supported_audio?(frame, state) do
      case safe_send_audio(state.transport_module, state.transport, frame.payload) do
        :ok ->
          acknowledge_audio(ingress, reference, frame.sequence_number, :ok)
          {:noreply, state}

        {:error, _reason} ->
          acknowledge_audio(ingress, reference, frame.sequence_number, {:error, :unavailable})
          stop_unavailable(:transport_closed, state)
      end
    else
      acknowledge_audio(ingress, reference, frame.sequence_number, {:error, :unsupported_audio})
      stop_unavailable(:unsupported_audio, state)
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, transport, {:message, payload}},
        %{transport: transport} = state
      ) do
    case state.provider_module.decode(payload) do
      {:ok, %Signal{} = signal} -> handle_signal(signal, state)
      {:ignore, _reason} -> {:noreply, state}
      {:error, _reason} -> stop_unavailable(:invalid_provider_message, state)
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, transport, {:closed, _reason}},
        %{transport: transport} = state
      ) do
    stop_unavailable(:transport_closed, state)
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

  defp handle_signal(%Signal{provider_sequence: sequence}, state)
       when sequence <= state.last_provider_sequence do
    {:noreply, state}
  end

  defp handle_signal(%Signal{kind: :failed} = signal, state) do
    send(state.owner, {:vxpipe_stt_signal, self(), state.identity, signal})

    stop_unavailable(:provider_failed, %{state | last_provider_sequence: signal.provider_sequence})
  end

  defp handle_signal(%Signal{} = signal, state) do
    send(state.owner, {:vxpipe_stt_signal, self(), state.identity, signal})
    {:noreply, %{state | last_provider_sequence: signal.provider_sequence}}
  end

  defp supported_audio?(frame, state) do
    frame.tenant_id == state.identity.tenant_id and
      frame.room_id == state.identity.room_id and
      frame.incarnation_id == state.identity.incarnation_id and
      frame.participant_id == state.identity.participant_id and
      frame.connection_id == state.identity.connection_id and
      frame.codec == state.media_format.codec and
      frame.sample_rate == state.media_format.sample_rate and
      frame.channels in [1, 2] and
      is_binary(frame.payload) and byte_size(frame.payload) > 0 and
      byte_size(frame.payload) <= @maximum_audio_bytes
  end

  defp stop_unavailable(reason, state) do
    send(state.owner, {:vxpipe_stt_unavailable, self(), state.identity, reason})
    {:stop, reason, state}
  end

  defp acknowledge_audio(ingress, reference, sequence_number, result) do
    send(
      ingress,
      {:vxpipe_stt_audio_result, self(), reference, sequence_number, result}
    )
  end

  defp safe_send_audio(module, transport, audio) do
    try do
      module.send_audio(transport, audio)
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
