defmodule Vxpipe.Providers.ElevenLabs.AgentLeaseSupervisor do
  @moduledoc false
  use DynamicSupervisor

  alias Vxpipe.Providers.ElevenLabs.AgentLease

  def start_link(options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: Keyword.get(options, :name, __MODULE__))
  end

  def acquire(owner, client, definition, options \\ []) do
    supervisor = Keyword.get(options, :supervisor, __MODULE__)

    DynamicSupervisor.start_child(
      supervisor,
      {AgentLease,
       Keyword.merge(options,
         supervisor: supervisor,
         owner: owner,
         client: client,
         definition: definition
       )}
    )
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
