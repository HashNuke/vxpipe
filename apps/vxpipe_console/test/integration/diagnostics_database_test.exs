defmodule Vxpipe.Console.Integration.DiagnosticsDatabaseTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.Test.DiagnosticsDatabase
  alias Vxpipe.Persistence.Repo

  @moduletag :integration

  test "scratch connection overrides the configured database URL without mutating it" do
    original = Application.fetch_env!(:vxpipe_persistence, Repo)
    on_exit(fn -> Application.put_env(:vxpipe_persistence, Repo, original) end)

    configured = [
      url: "ecto://fixture:fixture@localhost/configured_test?pool_size=99",
      pool: Ecto.Adapters.SQL.Sandbox
    ]

    Application.put_env(:vxpipe_persistence, Repo, configured)
    options = DiagnosticsDatabase.connection_options()

    {:ok, effective} =
      Ecto.Repo.Supervisor.init_config(:supervisor, Repo, :vxpipe_persistence, options)

    assert Keyword.fetch!(effective, :database) == Keyword.fetch!(options, :database)
    assert Keyword.fetch!(effective, :pool_size) == 10
    assert Keyword.fetch!(effective, :pool) == DBConnection.ConnectionPool
    assert Application.fetch_env!(:vxpipe_persistence, Repo) == configured
  end

  test "measurement database commits across connections and preserves configured database" do
    environment = Application.fetch_env!(:vxpipe_persistence, Repo)
    configured = Repo.config()
    options = DiagnosticsDatabase.start!()
    database = Keyword.fetch!(options, :database)
    assert database != Keyword.fetch!(configured, :database)
    assert String.starts_with?(database, "vxdiag_")
    assert Repo.query!("SELECT current_database()").rows == [[database]]
    refute Repo.in_transaction?()

    assert_raise RuntimeError, "diagnostic measurement requires an isolated Repo", fn ->
      DiagnosticsDatabase.start!()
    end

    options = Keyword.drop(options, [:name, :pool, :pool_size])
    reader = start_supervised!({Postgrex, options})
    writer_pid = Repo.query!("SELECT pg_backend_pid()").rows
    assert %{rows: reader_pid} = Postgrex.query!(reader, "SELECT pg_backend_pid()", [])
    refute writer_pid == reader_pid

    # The workload's settings table must be visible after a real committed write.
    Repo.query!(
      "UPDATE installation_diagnostics_settings SET revision = 7, updated_by = $1, updated_at = NOW()",
      [Ecto.UUID.bingenerate()]
    )

    assert %{rows: [[7]]} =
             Postgrex.query!(reader, "SELECT revision FROM installation_diagnostics_settings", [])

    assert Application.fetch_env!(:vxpipe_persistence, Repo) == environment
  end
end
