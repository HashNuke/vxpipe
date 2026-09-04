defmodule Vxpipe.CallEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Vxpipe.CallEngine.RoomRegistry},
      {Task.Supervisor, name: Vxpipe.CallEngine.ModelInferenceTaskSupervisor},
      Vxpipe.CallEngine.RoomSupervisor
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.CallEngine.Supervisor
    )
  end
end
