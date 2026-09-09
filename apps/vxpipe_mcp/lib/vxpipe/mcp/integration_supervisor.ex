defmodule Vxpipe.MCP.IntegrationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.MCP.ConnectionNames

  def start_link(opts) do
    key = Keyword.fetch!(opts, :key)
    Supervisor.start_link(__MODULE__, opts, name: ConnectionNames.via(:owner, key))
  end

  @impl true
  def init(opts) do
    key = Keyword.fetch!(opts, :key)
    runtime = Keyword.fetch!(opts, :runtime)

    client_options =
      opts
      |> Keyword.fetch!(:client_options)
      |> Keyword.merge(Keyword.get(opts, :runtime_options, []))
      |> Keyword.put(:name, ConnectionNames.via(:client, key))

    Supervisor.init([runtime.child_spec(client_options)], strategy: :one_for_one)
  end
end
