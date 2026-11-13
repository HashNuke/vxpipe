defmodule Vxpipe.Gateway.TestTelephonyLeg do
  use GenServer

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options) do
    {:ok,
     %{observer: Keyword.fetch!(options, :observer), result: Keyword.get(options, :result, :ok)}}
  end

  @impl true
  def handle_call({:event, event}, {source, _tag}, state) do
    send(state.observer, {:test_media_event, event, source})
    {:reply, state.result, state}
  end
end
