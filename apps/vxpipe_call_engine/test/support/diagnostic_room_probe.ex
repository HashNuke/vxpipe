defmodule Vxpipe.CallEngine.DiagnosticRoomProbe do
  @moduledoc false
  use GenServer

  def start_link(options),
    do:
      GenServer.start_link(__MODULE__, Keyword.fetch!(options, :state),
        name: Keyword.fetch!(options, :name)
      )

  def init(state), do: {:ok, state}

  def handle_call({:diagnostic_sources, _, _} = request, from, state),
    do: Vxpipe.CallEngine.RoomAuthority.handle_call(request, from, state)
end
