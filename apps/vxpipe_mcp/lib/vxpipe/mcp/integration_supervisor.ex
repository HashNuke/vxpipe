defmodule Vxpipe.MCP.IntegrationSupervisor do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Vxpipe.MCP.ConnectionNames

  def start_link(opts) do
    key = Keyword.fetch!(opts, :key)
    Supervisor.start_link(__MODULE__, opts, name: ConnectionNames.via(:owner, key))
  end

  @impl true
  def init(opts) do
    key = Keyword.fetch!(opts, :key)
    runtime = Keyword.fetch!(opts, :runtime)

    transport_supervisor =
      {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:transport_workers, self()}}}

    workers =
      Supervisor.child_spec(
        {DynamicSupervisor, strategy: :one_for_one, name: transport_supervisor},
        restart: :temporary,
        significant: true
      )

    client_options =
      opts
      |> Keyword.fetch!(:client_options)
      |> Keyword.merge(Keyword.get(opts, :runtime_options, []))
      |> Keyword.put(:name, ConnectionNames.via(:client, key))
      |> Keyword.put(:transport_supervisor, transport_supervisor)

    client =
      Supervisor.child_spec(runtime.child_spec(client_options),
        restart: :temporary,
        significant: true
      )

    Supervisor.init([workers, client], strategy: :one_for_one, auto_shutdown: :any_significant)
  end
end
