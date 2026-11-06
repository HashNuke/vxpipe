defmodule Vxpipe.Persistence.Integration.MCPConnectionConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Persistence.Schema.Tenant
  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP connection race", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keys} = CredentialKeyring.new("fixture", %{"fixture" => :crypto.strong_rand_bytes(32)})

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
      Sandbox.checkin(Repo)
    end)

    %{
      tenant: tenant.key,
      context: [repo: Repo, keyring: keys],
      attributes: %{
        endpoint: "https://mcp.example.test/mcp",
        endpoint_identity: "https://mcp.example.test/mcp",
        directory_id: "fixture",
        server_name: "Fixture",
        auth_method: "bearer",
        catalog: []
      }
    }
  end

  test "independent database clients return the same durable duplicate identity", data do
    operation = fn ->
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "fixture"})
    end

    results = race([operation, operation])
    assert [{:ok, saved}] = Enum.filter(results, &match?({:ok, _}, &1))

    assert [{:error, {:mcp_connection_exists, id}}] =
             Enum.filter(results, &match?({:error, _}, &1))

    assert id == saved.id
    assert {:ok, [^saved]} = ConnectionStore.list(data.context, data.tenant)
  end

  test "independent replacements cannot both consume the same generation", data do
    {:ok, saved} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "old"})

    tokens = ["first", "second"]

    results =
      race(
        Enum.map(tokens, fn token ->
          fn ->
            ConnectionStore.replace(data.context, data.tenant, saved.id, 1, data.attributes, %{
              "token" => token
            })
          end
        end)
      )

    assert [{:ok, updated}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, :stale_mcp_connection}] = Enum.filter(results, &match?({:error, _}, &1))
    assert updated.id == saved.id
    assert updated.generation == 2

    {winner, {:ok, _}} =
      Enum.find(Enum.zip(tokens, results), fn {_token, result} -> match?({:ok, _}, result) end)

    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, saved.id)
    assert resolved.secrets == %{"token" => winner}
  end

  defp race(operations) do
    observer = self()

    workers =
      operations
      |> Enum.with_index()
      |> Enum.map(fn {operation, index} ->
        pid =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:ready, self(), connection})

               receive do
                 :run -> send(observer, {:result, self(), operation.()})
               after
                 5_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end

               Sandbox.checkin(Repo)
             end},
            id: {:connection_racer, index}
          )

        {pid, Process.monitor(pid)}
      end)

    connections =
      Enum.map(workers, fn {pid, _} ->
        assert_receive {:ready, ^pid, connection}, 5_000
        connection
      end)

    assert length(Enum.uniq(connections)) == length(workers)
    Enum.each(workers, fn {pid, _} -> send(pid, :run) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end
end
