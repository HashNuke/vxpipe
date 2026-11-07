defmodule Vxpipe.Persistence.Test.MCPDatabaseNode do
  @moduledoc "Isolated BEAM/database fixture for durable MCP concurrency contracts."

  use Application

  alias Vxpipe.Persistence.Repo

  def boot(repository) do
    Application.put_env(
      :vxpipe_persistence,
      Repo,
      repository
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 1)
      |> Keyword.put(:log, false)
    )

    :ok =
      :application.load(
        {:application, :vxpipe_mcp_database_test,
         [
           vsn: ~c"1",
           applications: [:kernel, :stdlib, :elixir, :logger, :crypto, :ecto_sql, :postgrex],
           mod: {__MODULE__, []}
         ]}
      )

    {:ok, _} = Application.ensure_all_started(:vxpipe_mcp_database_test)
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
    %{os_pid: System.pid(), backend: backend}
  end

  @impl true
  def start(_type, _args),
    do: Supervisor.start_link([Repo], strategy: :one_for_one, name: __MODULE__.Supervisor)

  # The closure belongs to a compiled support module that both peers can load.
  def clock(now), do: fn -> now end
end
