defmodule Vxpipe.CallEngine.Capability.SpeechToText do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Capability.SpeechToText.Usage
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.Capability.SpeechToText.State

  @call_timeout 5_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec push_audio(pid(), AudioFrame.t()) ::
          :ok | {:error, :policy_denied | :unsupported_audio | :unavailable}
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

    case State.new(options) do
      {:ok, state} ->
        {:ok, Usage.start_session(state)}

      {:error, :transport_start_failed, provider_module} ->
        Telemetry.provider_failure(:stt, provider_module, :transport_closed)
        {:stop, :transport_start_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, frame}, _from, state) do
    case State.send_audio(state, frame) do
      :ok -> {:reply, :ok, Usage.accept_input(state)}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, _from, state) do
    case State.install_policy(state, snapshot) do
      {:ok, updated} ->
        state = Usage.transition(state, updated)
        {:reply, :ok, state}

      {:error, :transport_start_failed, updated} ->
        state = Usage.transition(state, updated)
        Telemetry.provider_failure(:stt, state.provider_module, :transport_closed)
        {:reply, {:error, :transport_start_failed}, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, _invalid}, _from, state) do
    {:reply, {:error, :invalid_policy}, state}
  end

  @impl true
  def handle_cast({:fail, reason}, state) do
    stop_unavailable(reason, state)
  end

  @impl true
  def handle_info({:vxpipe_stt_audio, ingress, reference, frame}, state)
      when is_pid(ingress) and is_reference(reference) do
    case State.send_audio(state, frame) do
      {:error, :unsupported_audio} ->
        acknowledge_audio(ingress, reference, frame.sequence_number, {:error, :unsupported_audio})
        stop_unavailable(:unsupported_audio, state)

      {:error, :policy_denied} ->
        acknowledge_audio(ingress, reference, frame.sequence_number, {:error, :policy_denied})
        {:noreply, state}

      {:error, :unavailable} ->
        acknowledge_audio(ingress, reference, frame.sequence_number, {:error, :unavailable})
        stop_unavailable(:transport_closed, state)

      :ok ->
        acknowledge_audio(ingress, reference, frame.sequence_number, :ok)
        {:noreply, Usage.accept_input(state)}
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
    _ = State.close(state)
    :ok
  end

  defp handle_signal(%Signal{provider_sequence: sequence}, state)
       when sequence <= state.last_provider_sequence do
    {:noreply, state}
  end

  defp handle_signal(%Signal{kind: :failed} = signal, state) do
    signal = %{signal | policy_revision: state.policy_revision}
    state = Usage.observe_signal(state, signal)
    send(state.owner, {:vxpipe_stt_signal, self(), state.identity, signal})

    stop_unavailable(:provider_failed, %{state | last_provider_sequence: signal.provider_sequence})
  end

  defp handle_signal(%Signal{} = signal, state) do
    signal = %{signal | policy_revision: state.policy_revision}
    state = Usage.observe_signal(state, signal)
    send(state.owner, {:vxpipe_stt_signal, self(), state.identity, signal})
    {:noreply, %{state | last_provider_sequence: signal.provider_sequence}}
  end

  defp stop_unavailable(reason, state) do
    state = Usage.finish_session(state, :failed)
    maybe_report_provider_failure(reason, state.provider_module)
    send(state.owner, {:vxpipe_stt_unavailable, self(), state.identity, reason})
    {:stop, reason, state}
  end

  defp maybe_report_provider_failure(reason, provider)
       when reason in [:transport_closed, :invalid_provider_message, :provider_failed] do
    Telemetry.provider_failure(:stt, provider, reason)
  end

  defp maybe_report_provider_failure(_reason, _provider), do: :ok

  defp acknowledge_audio(ingress, reference, sequence_number, result) do
    send(
      ingress,
      {:vxpipe_stt_audio_result, self(), reference, sequence_number, result}
    )
  end
end
