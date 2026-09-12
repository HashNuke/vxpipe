defmodule Vxpipe.Calls.PublicationSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(_options), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: Vxpipe.Calls.PublicationRegistry},
      {Task.Supervisor, name: Vxpipe.Calls.PublicationTaskSupervisor},
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: Vxpipe.Calls.PublicationFinalizerSupervisor,
       max_children: 1_024},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Vxpipe.Calls.PublicationWorkerSupervisor, max_children: 1_024}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
