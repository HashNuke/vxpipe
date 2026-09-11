defmodule Vxpipe.Gateway.TestTelephonyLeg do
  use GenServer

  def start_link(options),
    do: GenServer.start_link(__MODULE__, Keyword.fetch!(options, :observer))

  @impl true
  def init(observer), do: {:ok, observer}

  @impl true
  def handle_call({:event, event}, {source, _tag}, observer) do
    send(observer, {:test_media_event, event, source})
    {:reply, :ok, observer}
  end
end
