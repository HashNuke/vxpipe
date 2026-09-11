defmodule Vxpipe.Artifacts.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Vxpipe.Artifacts.Registry},
      {Task.Supervisor, name: Vxpipe.Artifacts.WriterTaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Vxpipe.Artifacts.WriterSupervisor},
      {Task.Supervisor, name: Vxpipe.Artifacts.MetadataTaskSupervisor},
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: Vxpipe.Artifacts.MetadataPublisherSupervisor,
       max_children: 1_024}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Artifacts.Supervisor
    )
  end
end
