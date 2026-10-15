defmodule Vxpipe.CallEngine.Speech.ContextTTSSession do
  @moduledoc "Owns one capability socket across context-identified utterances."

  use GenServer

  alias Vxpipe.CallEngine.Speech.{
    Channel,
    ContextTTSSocket,
    Event,
    Playback,
    SessionTree,
    TTSProvider
  }

  @request_timeout 60_000
  @idle_keepalive_interval 15_000

  @derive {Inspect, only: [:request, :cancelling?, :pending_done?]}
  defstruct [
    :allocation,
    :providers,
    :wire_options,
    :wire_monitor,
    :setup_timer,
    :cancel_timer,
    :cancel_timeout_ms,
    :channel,
    :provider,
    :config,
    :request,
    :context,
    :last_terminal_request,
    :request_timer,
    :awaiting,
    :wire,
    :wire_module,
    :idle_timer,
    :keepalive_id,
    cancelling?: false,
    pending_done?: false
  ]

  def start_link(options, provider),
    do: TTSProvider.start_link(__MODULE__, Keyword.put(options, :context_provider, provider))

  def speak(pid, reference, text), do: GenServer.call(pid, {:speak, reference, text}, 5_000)

  def cancel(pid, reference, playback),
    do: GenServer.call(pid, {:cancel, reference, playback}, 5_000)

  def close(pid) do
    GenServer.call(pid, :close, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @impl true
  def init(options) do
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    provider = Keyword.fetch!(options, :context_provider)
    wire_module = Keyword.get(private, :wire_module, ContextTTSSocket)
    wire_options = Keyword.get(private, :wire_options, [])

    allocation = Keyword.fetch!(options, :allocation)
    cancel_timeout = Keyword.get(private, :cancel_timeout_ms, 5_000)

    with {:ok, expected} <- provider.request_configuration(config),
         true <- descriptor == expected,
         true <- is_atom(wire_module) and is_list(wire_options) and Keyword.keyword?(wire_options),
         true <- is_integer(cancel_timeout) and cancel_timeout in 1..5_000,
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         allocation: allocation,
         providers: SessionTree.providers(allocation),
         channel: channel,
         provider: provider,
         config: config,
         wire_module: wire_module,
         wire_options: wire_options,
         cancel_timeout_ms: cancel_timeout,
         keepalive_id: keepalive_identity(provider)
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    options = [
      owner: self(),
      connection: state.provider.connection_options(state.config),
      transport_options: state.wire_options,
      provider: state.provider
    ]

    case DynamicSupervisor.start_child(state.providers, %{
           id: state.wire_module,
           start: {state.wire_module, :start_link, [options]},
           restart: :temporary,
           shutdown: :brutal_kill
         }) do
      {:ok, wire} ->
        remaining = max(state.allocation.deadline - System.monotonic_time(:millisecond), 1)

        {:noreply,
         %{
           state
           | wire: wire,
             wire_monitor: Process.monitor(wire),
             setup_timer: Process.send_after(self(), :setup_timeout, remaining)
         }}

      _failure ->
        fail(state)
    end
  end

  @impl true
  def handle_call({:speak, reference, text}, _from, %{request: nil} = state) do
    with :ok <- state.provider.validate_text(text),
         {:ok, context} <- state.provider.new_context_id(),
         :ok <- send_utterance(state, context, text),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ) do
      timer = Process.send_after(self(), {:request_timeout, reference}, @request_timeout)

      {:reply, :ok,
       %{
         cancel_idle(state)
         | request: reference,
           context: context,
           request_timer: timer,
           last_terminal_request: nil,
           idle_timer: nil
       }}
    else
      {:error, :invalid_text} -> {:reply, {:error, :invalid_text}, state}
      _failure -> fail_call(state)
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ),
      do: {:reply, :ok, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference} = state
      ) do
    state = release_awaiting(state)
    state = %{state | cancelling?: true}

    result =
      if state.pending_done?,
        do: :ok,
        else: send_cancel(state)

    with :ok <- result,
         {:ok, state} <- maybe_finish(state) do
      timer =
        if state.request,
          do: Process.send_after(self(), {:cancel_timeout, reference}, state.cancel_timeout_ms)

      {:reply, :ok, %{state | cancel_timer: timer}}
    else
      _failure -> fail_call(state)
    end
  end

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(:close, _from, state) do
    if state.wire do
      _ = state.wire_module.close(state.wire, state.provider.close_socket(state.config))
    end

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:vxpipe_socket_connected, wire}, %{wire: wire, setup_timer: timer} = state)
      when is_reference(timer) do
    Process.cancel_timer(timer)

    case Event.emit(state.channel, :ready, readiness: :initialized) do
      :ok -> {:noreply, %{state | setup_timer: nil, idle_timer: schedule_idle()}}
      _failure -> fail(state)
    end
  end

  def handle_info(:setup_timeout, %{setup_timer: timer} = state) when is_reference(timer),
    do: fail(state)

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{wire_monitor: monitor} = state),
    do: fail(state)

  def handle_info(
        {:vxpipe_tts_transport, wire, {:audio, wire_ref, {context, audio}}},
        %{wire: wire} = state
      ) do
    cond do
      state.request == nil or state.cancelling? or context != state.context ->
        acknowledge_wire(state, wire_ref)
        {:noreply, state}

      state.awaiting != nil ->
        {:stop, :normal, state}

      true ->
        case state.provider.validate_audio(audio) do
          {:audio, audio} ->
            case submit_frame(state, wire_ref, audio) do
              {:ok, state} -> {:noreply, state}
              _failure -> fail(state)
            end

          _invalid ->
            {:stop, :normal, state}
        end
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, wire, {:control, {:final, context}}},
        %{wire: wire} = state
      ) do
    if state.request != nil and context == state.context do
      state = %{state | pending_done?: true}

      case maybe_finish(state) do
        {:ok, state} -> {:noreply, state}
        _failure -> {:stop, :normal, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, wire, {:control, {:error, _reason}}},
        %{wire: wire} = state
      ),
      do: {:stop, :normal, state}

  def handle_info({:vxpipe_tts_transport, wire, {:closed, _reason}}, %{wire: wire} = state),
    do: {:stop, :normal, state}

  def handle_info({:request_timeout, request}, %{request: request} = state),
    do: {:stop, :normal, state}

  def handle_info({:request_timeout, _old_request}, state), do: {:noreply, state}

  def handle_info({:cancel_timeout, request}, %{request: request, cancel_timer: timer} = state)
      when is_reference(timer), do: fail(state)

  def handle_info(
        {:idle_keepalive, identity},
        %{request: nil, idle_timer: {_timer, identity}} = state
      ) do
    state = %{state | idle_timer: nil}

    cond do
      is_nil(state.keepalive_id) ->
        {:noreply, %{state | idle_timer: schedule_idle()}}

      payload = state.provider.keepalive_payload(state.config, state.keepalive_id) ->
        case state.wire_module.send_control(state.wire, payload) do
          :ok -> {:noreply, %{state | idle_timer: schedule_idle()}}
          _failure -> {:stop, :normal, state}
        end

      true ->
        {:noreply, %{state | idle_timer: schedule_idle()}}
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, request, credit, :ok},
        %{channel: channel, request: request, awaiting: {credit, wire_ref, remaining}} = state
      ) do
    with {:ok, state} <- submit_frame(%{state | awaiting: nil}, wire_ref, remaining),
         {:ok, state} <- maybe_finish(state) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :context_tts)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp send_utterance(state, context, text) do
    Enum.reduce_while(state.provider.open_utterance(state.config, context, text), :ok, fn payload,
                                                                                          :ok ->
      case state.wire_module.send_control(state.wire, payload) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end)
  end

  defp maybe_finish(%{pending_done?: true, awaiting: nil, request: request} = state) do
    kind = if state.cancelling?, do: :cancelled, else: :completed

    result =
      case Event.emit(state.channel, kind, request_ref: request) do
        {:error, :cancelled} -> Event.emit(state.channel, :cancelled, request_ref: request)
        other -> other
      end

    with :ok <- result do
      if state.request_timer, do: Process.cancel_timer(state.request_timer)
      if state.cancel_timer, do: Process.cancel_timer(state.cancel_timer)

      {:ok,
       %{
         state
         | request: nil,
           context: nil,
           request_timer: nil,
           cancel_timer: nil,
           last_terminal_request: request,
           cancelling?: false,
           pending_done?: false,
           idle_timer: schedule_idle()
       }}
    end
  end

  defp maybe_finish(state), do: {:ok, state}

  defp send_cancel(state) do
    case state.provider.cancel_utterance(state.config, state.context) do
      nil -> :ok
      payload -> state.wire_module.send_control(state.wire, payload)
    end
  end

  defp submit_frame(state, wire_ref, "") do
    acknowledge_wire(state, wire_ref)
    {:ok, state}
  end

  defp submit_frame(state, wire_ref, audio) do
    size = min(byte_size(audio), 65_536)
    <<chunk::binary-size(size), remaining::binary>> = audio

    case Channel.submit(state.channel, state.request, chunk) do
      {:ok, credit} ->
        {:ok, %{state | awaiting: {credit, wire_ref, remaining}}}

      {:error, :stale_request} ->
        acknowledge_wire(state, wire_ref)
        {:ok, state}

      failure ->
        failure
    end
  end

  defp release_awaiting(%{awaiting: {_credit, wire_ref, _remaining}} = state) do
    acknowledge_wire(state, wire_ref)
    %{state | awaiting: nil}
  end

  defp release_awaiting(state), do: state

  defp acknowledge_wire(state, reference) do
    send(state.wire, {:vxpipe_tts_audio_result, self(), reference, :ok})
  end

  defp schedule_idle do
    identity = make_ref()
    {Process.send_after(self(), {:idle_keepalive, identity}, @idle_keepalive_interval), identity}
  end

  defp cancel_idle(%{idle_timer: nil} = state), do: state

  defp cancel_idle(%{idle_timer: {timer, _identity}} = state) do
    Process.cancel_timer(timer)
    %{state | idle_timer: nil}
  end

  defp keepalive_identity(provider) do
    case provider.new_context_id() do
      {:ok, identity} -> identity
      _invalid -> nil
    end
  end

  defp fail(state), do: {:stop, {:shutdown, :session_failed}, state}

  defp fail_call(state), do: {:stop, :normal, {:error, :provider_unavailable}, state}
end
