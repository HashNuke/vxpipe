defmodule Vxpipe.Gateway.TestTelephonySocket do
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.fetch!(options, :observer))
  end

  def run(socket, operation) when is_pid(socket) and is_function(operation, 0) do
    GenServer.call(socket, {:run, operation}, 10_000)
  end

  @impl true
  def init(observer), do: {:ok, observer}

  @impl true
  def handle_call({:run, operation}, _from, observer) do
    {:reply, operation.(), observer}
  end

  @impl true
  def handle_info({:vxpipe_telnyx_socket_send, message}, observer) do
    send(observer, {:test_telnyx_socket_send, message})
    {:noreply, observer}
  end

  def handle_info({:vxpipe_twilio_socket_send, message}, observer) do
    send(observer, {:test_twilio_socket_send, message})
    {:noreply, observer}
  end

  def handle_info({:vxpipe_twilio_socket_clear, message}, observer) do
    send(observer, {:test_twilio_socket_clear, message})
    {:noreply, observer}
  end
end
