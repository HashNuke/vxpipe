defmodule Vxpipe.Gateway.TestTelephonySocket do
  use GenServer

  alias Vxpipe.Gateway.Telephony.{PlaybackMarks, SocketReadiness}

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.fetch!(options, :observer))
  end

  def run(socket, operation) when is_pid(socket) and is_function(operation, 0) do
    GenServer.call(socket, {:run, operation}, 10_000)
  end

  def bind_readiness(socket, binding, stream_id),
    do: GenServer.call(socket, {:bind_readiness, binding, stream_id})

  def open(socket, callback, operation),
    do: GenServer.call(socket, {:open, callback, operation}, 10_000)

  def input(socket, packet), do: GenServer.call(socket, {:input, packet}, 5_000)

  def automatic_marks(socket, enabled?), do: GenServer.call(socket, {:automatic_marks, enabled?})

  def acknowledge_mark(socket, name), do: GenServer.call(socket, {:acknowledge_mark, name})

  def media_timestamp(socket), do: GenServer.call(socket, :media_timestamp)

  @impl true
  def init(observer),
    do:
      {:ok,
       %{
         observer: observer,
         readiness: nil,
         callback: nil,
         socket: nil,
         sequence: 10,
         automatic_marks?: true,
         media_started_ms: nil
       }}

  @impl true
  def handle_call({:run, operation}, _from, state) do
    {:reply, operation.(), state}
  end

  def handle_call({:automatic_marks, enabled?}, _from, state) do
    {:reply, :ok, %{state | automatic_marks?: enabled?}}
  end

  def handle_call({:acknowledge_mark, name}, _from, state) do
    {:reply, :ok, acknowledge(%{"event" => "mark", "mark" => %{"name" => name}}, state)}
  end

  def handle_call(:media_timestamp, _from, state) do
    now = System.monotonic_time(:millisecond)
    started = state.media_started_ms || now
    {:reply, now - started, %{state | media_started_ms: started}}
  end

  def handle_call({:open, callback, operation}, _from, state) do
    case operation.() do
      {:ok, binding, socket} = result ->
        {:reply, result,
         %{
           state
           | callback: callback,
             socket: socket,
             readiness: %{
               binding: binding,
               stream_id: socket.stream_id,
               readiness_resource: socket.readiness_resource
             }
         }}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:input, packet}, _from, state) do
    {message, _metadata} = packet

    started =
      if JSON.decode!(message)["event"] == "media",
        do: state.media_started_ms || System.monotonic_time(:millisecond),
        else: state.media_started_ms

    state = %{state | media_started_ms: started}

    case state.callback.handle_in(packet, state.socket) do
      {:ok, socket} = result -> {:reply, result, %{state | socket: socket}}
      other -> {:reply, other, state}
    end
  end

  def handle_call({:bind_readiness, binding, stream_id}, _from, state) do
    readiness = %{
      binding: binding,
      stream_id: stream_id,
      readiness_resource: SocketReadiness.new(binding)
    }

    {:reply, :ok, %{state | readiness: readiness}}
  end

  @impl true
  def handle_info(message, %{callback: callback} = state) when not is_nil(callback) do
    case callback.handle_info(message, state.socket) do
      {:ok, socket} ->
        {:noreply, %{state | socket: socket}}

      {:push, frames, socket} ->
        state = %{state | socket: socket}
        {:noreply, Enum.reduce(List.wrap(frames), state, &deliver/2)}

      {:stop, reason, socket} ->
        {:stop, reason, %{state | socket: socket}}

      {:stop, reason, _close_frame, socket} ->
        {:stop, reason, %{state | socket: socket}}
    end
  end

  def handle_info({:vxpipe_telnyx_socket_send, message}, state) do
    send(state.observer, {:test_telnyx_socket_send, message})
    {:noreply, state}
  end

  def handle_info({:vxpipe_twilio_socket_send, message}, state) do
    send(state.observer, {:test_twilio_socket_send, message})
    {:noreply, state}
  end

  def handle_info({:vxpipe_twilio_socket_clear, message}, state) do
    send(state.observer, {:test_twilio_socket_clear, message})
    {:noreply, state}
  end

  def handle_info({:vxpipe_phone_readiness, receiver, reference}, %{readiness: readiness} = state)
      when not is_nil(readiness) do
    SocketReadiness.reply(readiness, receiver, reference)
    {:noreply, state}
  end

  def handle_info({:vxpipe_playback_command, stream_id, action, receiver, request}, state) do
    provider = state.readiness.binding.provider

    {:ok, frames, marks} =
      PlaybackMarks.command(%PlaybackMarks{}, provider, stream_id, action, receiver, request)

    Enum.each(frames, fn {:text, message} ->
      case JSON.decode!(message) do
        %{"event" => "mark", "mark" => %{"name" => name}} ->
          PlaybackMarks.acknowledge(marks, name)

        _clear ->
          :ok
      end
    end)

    {:noreply, state}
  end

  defp deliver({:text, message}, state) do
    send(state.observer, {:test_phone_output, self(), message})

    case JSON.decode!(message) do
      %{"event" => "mark"} = mark when state.automatic_marks? ->
        acknowledge(mark, state)

      _audio_clear_or_held_mark ->
        state
    end
  end

  defp acknowledge(mark, state) do
    mark =
      case state.socket.binding.provider do
        :telnyx ->
          Map.merge(mark, %{
            "stream_id" => state.socket.stream_id,
            "sequence_number" => state.sequence
          })

        :twilio ->
          Map.merge(mark, %{
            "streamSid" => state.socket.stream_id,
            "sequenceNumber" => Integer.to_string(state.sequence)
          })
      end

    {:ok, socket} =
      state.callback.handle_in({JSON.encode!(mark), opcode: :text}, state.socket)

    %{state | socket: socket, sequence: state.sequence + 1}
  end
end
