defmodule Vxpipe.MCP.IntegrationSupervisor do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Vxpipe.MCP.{ConnectionNames, SessionStartup}

  def start_link(opts) do
    key = Keyword.fetch!(opts, :key)
    scope = Keyword.get(opts, :scope)

    metadata = %{
      parent: Keyword.fetch!(opts, :parent),
      policy: Keyword.fetch!(opts, :policy),
      runtime: Keyword.fetch!(opts, :runtime)
    }

    Supervisor.start_link(__MODULE__, opts,
      name: ConnectionNames.via(:owner, key, scope, metadata)
    )
  end

  @impl true
  def init(opts) do
    key = Keyword.fetch!(opts, :key)
    runtime = Keyword.fetch!(opts, :runtime)
    scope = Keyword.get(opts, :scope)

    startup =
      Supervisor.child_spec(
        {SessionStartup,
         integration: self(),
         host: Keyword.fetch!(opts, :parent),
         caller: Keyword.fetch!(opts, :caller),
         deadline: Keyword.fetch!(opts, :deadline)},
        significant: true
      )

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
      |> Keyword.put(
        :name,
        ConnectionNames.via(:client, key, scope, %{integration_owner: self()})
      )
      |> Keyword.put(:transport_supervisor, transport_supervisor)
      |> Keyword.put(:defer_connection, true)

    client =
      Supervisor.child_spec(runtime.child_spec(client_options),
        restart: :temporary,
        significant: true
      )

    Supervisor.init([startup, workers, client],
      strategy: :one_for_one,
      auto_shutdown: :any_significant
    )
  end
end
