defmodule Vxpipe.CallEngine.Speech.Socket do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Speech.SocketConnection

  @typedoc """
  Observed peer-close metadata, not proof of successful application draining.

  Mint normalizes empty close payloads to 1000, so that decoded code represents
  either a normal status or no status. Other decoded codes are preserved.
  """
  @type peer_close_status :: :normal_or_no_status | non_neg_integer()

  @callback handle_frame(tuple(), map()) :: {:ok, map()} | {:await, reference(), map()}
  @callback handle_disconnect(term(), map()) :: {:ok, map()}
  @callback handle_peer_close(peer_close_status(), map()) :: {:ok, map()}
  @callback handle_peer_close(peer_close_status(), binary(), map()) :: {:ok, map()}
  @callback keepalive_frame(map()) :: tuple()
  @optional_callbacks handle_peer_close: 2, handle_peer_close: 3, keepalive_frame: 1

  @send_timeout 5_000
  @output_timeout 15_000

  @derive {Inspect, only: [:callback, :keepalive_interval]}
  defstruct [
    :connection,
    :callback,
    :callback_state,
    :keepalive_interval,
    :awaiting,
    :pending_message,
    :connect_options,
    :transport_options,
    pending_frames: [],
    retiring?: false
  ]

  def start_link(options, callback, callback_state) do
    GenServer.start_link(__MODULE__, {options, callback, callback_state})
  end

  def send_frame(socket, frame), do: request(socket, {:send, frame})
  def close(socket, payload), do: request(socket, {:close, payload})
  def retire(socket), do: GenServer.cast(socket, :retire)

  @impl true
  def handle_cast(:retire, %{retiring?: true} = state), do: {:noreply, state}

  def handle_cast(:retire, state) do
    case SocketConnection.send_frame(state.connection, {:close, 1_000, ""}) do
      {:ok, connection} -> {:noreply, %{state | connection: connection, retiring?: true}}
      {:error, _reason} -> {:stop, :normal, disconnect(state)}
    end
  end

  @impl true
  def init({options, callback, callback_state}) do
    transport_options = Keyword.fetch!(options, :transport_options)

    if Keyword.get(options, :connect_mode) == :deferred do
      {:ok,
       %__MODULE__{
         callback: callback,
         callback_state: callback_state,
         connect_options: Keyword.fetch!(options, :connection),
         transport_options: transport_options
       }, {:continue, :connect}}
    else
      connect(Keyword.fetch!(options, :connection), transport_options, callback, callback_state)
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    case SocketConnection.open(state.connect_options, state.transport_options) do
      {:ok, connection, frames} ->
        schedule_keepalive(Map.get(state.callback_state, :keepalive_interval))
        send(state.callback_state.owner, {:vxpipe_socket_connected, self()})

        {:noreply,
         %{
           state
           | connection: connection,
             connect_options: nil,
             transport_options: nil,
             keepalive_interval: Map.get(state.callback_state, :keepalive_interval)
         }, {:continue, {:frames, frames}}}

      {:error, _reason} ->
        {:stop, :normal, disconnect(state)}
    end
  end

  def handle_continue({:frames, frames}, state), do: handle_frames(frames, state)

  defp connect(connection_options, transport_options, callback, callback_state) do
    case SocketConnection.open(connection_options, transport_options) do
      {:ok, connection, frames} ->
        keepalive_interval = Map.get(callback_state, :keepalive_interval)
        schedule_keepalive(keepalive_interval)

        {:ok,
         %__MODULE__{
           connection: connection,
           callback: callback,
           callback_state: callback_state,
           keepalive_interval: keepalive_interval,
           awaiting: nil,
           pending_frames: [],
           pending_message: nil
         }, {:continue, {:frames, frames}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:send, _frame}, _from, %{retiring?: true} = state),
    do: {:reply, {:error, :retiring}, state}

  @impl true
  def handle_call({:send, _frame}, _from, %{connection: nil} = state),
    do: {:reply, {:error, :not_ready}, state}

  def handle_call({:close, _payload}, _from, %{connection: nil} = state),
    do: {:stop, :normal, :ok, state}

  def handle_call({:send, frame}, _from, state) do
    case SocketConnection.send_frame(state.connection, frame) do
      {:ok, connection} -> {:reply, :ok, %{state | connection: connection}}
      {:error, _reason} -> {:stop, :normal, {:error, :connection_lost}, disconnect(state)}
    end
  end

  def handle_call({:close, payload}, _from, state) do
    result =
      with {:ok, connection} <- SocketConnection.send_frame(state.connection, {:text, payload}),
           {:ok, _connection} <- SocketConnection.send_frame(connection, :close) do
        :ok
      end

    {:stop, :normal, result, state}
  end

  @impl true
  def handle_info({:vxpipe_tts_audio_result, owner, reference, result}, state) do
    case state.awaiting do
      {^reference, timer} when owner == state.callback_state.owner ->
        Process.cancel_timer(timer)

        if result == :ok do
          handle_frames(state.pending_frames, %{state | awaiting: nil, pending_frames: []})
        else
          {:stop, :normal, disconnect(state)}
        end

      _stale_or_untrusted ->
        {:noreply, state}
    end
  end

  def handle_info({:output_timeout, reference}, %{awaiting: {reference, _timer}} = state),
    do: {:stop, :normal, disconnect(state)}

  def handle_info({:output_timeout, _reference}, state), do: {:noreply, state}

  def handle_info(:keepalive, %{connection: nil} = state), do: {:noreply, state}

  def handle_info(:keepalive, state) do
    frame =
      if function_exported?(state.callback, :keepalive_frame, 1),
        do: state.callback.keepalive_frame(state.callback_state),
        else: :ping

    case SocketConnection.send_frame(state.connection, frame) do
      {:ok, connection} ->
        schedule_keepalive(state.keepalive_interval)
        {:noreply, %{state | connection: connection}}

      {:error, _reason} ->
        {:stop, :normal, disconnect(state)}
    end
  end

  def handle_info(_message, %{connection: nil} = state), do: {:noreply, state}

  def handle_info(message, %{awaiting: awaiting} = state) when awaiting != nil do
    # Mint uses active-once delivery. Leave the one pending socket message unconsumed
    # until output is acknowledged; do not re-arm a growing provider audio queue.
    if SocketConnection.message?(state.connection, message) do
      {:noreply, %{state | pending_message: message}}
    else
      {:noreply, state}
    end
  end

  def handle_info(message, state) do
    case SocketConnection.receive_frames(state.connection, message) do
      {:ok, connection, frames} -> handle_frames(frames, %{state | connection: connection})
      {:error, _reason} -> {:stop, :normal, disconnect(state)}
    end
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, %{transport: :speech_websocket})
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  @impl true
  def terminate(_reason, %{connection: nil}), do: :ok
  def terminate(_reason, state), do: SocketConnection.close(state.connection)

  defp handle_frames([], %{pending_message: nil} = state), do: {:noreply, state}

  defp handle_frames([], state) do
    handle_info(state.pending_message, %{state | pending_message: nil})
  end

  defp handle_frames([{:ping, payload} | rest], state) do
    case SocketConnection.send_frame(state.connection, {:pong, payload}) do
      {:ok, connection} -> handle_frames(rest, %{state | connection: connection})
      {:error, _reason} -> {:stop, :normal, disconnect(state)}
    end
  end

  defp handle_frames([{:pong, _payload} | rest], state), do: handle_frames(rest, state)

  defp handle_frames([{:close, code, _reason} | _rest], %{retiring?: true} = state)
       when code in [1_000, 1_001] do
    :ok = SocketConnection.close(state.connection)
    send(state.callback_state.owner, {:vxpipe_socket_retired, self()})
    {:stop, :normal, %{state | connection: nil}}
  end

  defp handle_frames([{:close, code, reason} | _rest], state) do
    _ = SocketConnection.send_frame(state.connection, {:close, 1_000, ""})
    {:stop, :normal, peer_close(state, code, reason)}
  end

  defp handle_frames([frame | rest], state) do
    case state.callback.handle_frame(frame, state.callback_state) do
      {:ok, callback_state} ->
        handle_frames(rest, %{state | callback_state: callback_state})

      {:await, reference, callback_state} ->
        timer = Process.send_after(self(), {:output_timeout, reference}, @output_timeout)

        {:noreply,
         %{
           state
           | callback_state: callback_state,
             awaiting: {reference, timer},
             pending_frames: rest
         }}
    end
  end

  defp disconnect(state) do
    {:ok, callback_state} =
      state.callback.handle_disconnect(:connection_lost, state.callback_state)

    %{state | callback_state: callback_state}
  end

  defp peer_close(state, code, reason) do
    status = if code == 1_000, do: :normal_or_no_status, else: code

    cond do
      function_exported?(state.callback, :handle_peer_close, 3) ->
        {:ok, callback_state} =
          state.callback.handle_peer_close(status, reason, state.callback_state)

        %{state | callback_state: callback_state}

      function_exported?(state.callback, :handle_peer_close, 2) ->
        {:ok, callback_state} = state.callback.handle_peer_close(status, state.callback_state)
        %{state | callback_state: callback_state}

      true ->
        disconnect(state)
    end
  end

  defp schedule_keepalive(nil), do: :ok
  defp schedule_keepalive(interval), do: Process.send_after(self(), :keepalive, interval)

  defp request(socket, message) do
    GenServer.call(socket, message, @send_timeout)
  catch
    :exit, _reason -> {:error, :connection_lost}
  end
end
