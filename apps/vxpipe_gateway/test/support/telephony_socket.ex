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

  @impl true
  def init(observer), do: {:ok, %{observer: observer, readiness: nil}}

  @impl true
  def handle_call({:run, operation}, _from, state) do
    {:reply, operation.(), state}
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
end
