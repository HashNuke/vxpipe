defmodule Vxpipe.Console.Test.DiagnosticsDatabase do
  @moduledoc "Disposable, migrated database with real commits for diagnostic measurements."

  alias Vxpipe.Persistence.Repo

  def start! do
    if Process.whereis(Repo), do: raise("diagnostic measurement requires an isolated Repo")

    options = connection_options()
    database = Keyword.fetch!(options, :database)

    # Register deletion only after this invocation created the exact database.
    IO.puts("DIAGNOSTIC_DATABASE_RESERVED " <> database)
    :ok = Ecto.Adapters.Postgres.storage_up(options)

    ExUnit.Callbacks.on_exit(fn ->
      :ok = Ecto.Adapters.Postgres.storage_down(options)
      IO.puts("DIAGNOSTIC_DATABASE_DROPPED " <> database)
    end)

    ExUnit.Callbacks.start_supervised!({Repo, options})
    migrations = Application.app_dir(:vxpipe_persistence, "priv/repo/migrations")
    Ecto.Migrator.run(Repo, migrations, :up, all: true, log: false)
    options
  end

  def connection_options do
    run_id = System.get_env("VXPIPE_DIAGNOSTIC_RUN_ID") || random_id()

    if not Regex.match?(~r/\A[0-9a-f]{32}\z/, run_id),
      do: raise("invalid diagnostic run identity")

    database = "vxdiag_" <> run_id <> "_" <> String.slice(random_id(), 0, 8)

    Repo.config()
    |> Keyword.put(:url, nil)
    |> Keyword.put(:database, database)
    |> Keyword.put(:pool, DBConnection.ConnectionPool)
    |> Keyword.put(:pool_size, 10)
  end

  defp random_id, do: String.replace(Ecto.UUID.generate(), "-", "")
end
