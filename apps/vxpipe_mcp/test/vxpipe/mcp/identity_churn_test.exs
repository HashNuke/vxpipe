defmodule Vxpipe.MCP.IdentityChurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{Catalog, Connection, ConnectionKey, Connections, ReadyClientRuntime}

  @churn_count 250
  @max_runtime_growth 5

  test "integration and catalog churn does not create proportional atoms or modules" do
    churn_once(0)
    _ = :code.all_loaded()
    atoms_before = :erlang.system_info(:atom_count)
    modules_before = loaded_modules()

    Enum.each(1..@churn_count, &churn_once/1)
    :erlang.garbage_collect()

    atom_growth = :erlang.system_info(:atom_count) - atoms_before
    module_growth = MapSet.size(MapSet.difference(loaded_modules(), modules_before))

    assert atom_growth <= @max_runtime_growth
    assert module_growth <= @max_runtime_growth
  end

  test "the same remote name resolves only within the supplied catalog" do
    first = catalog_with_scope("tenant-one")
    second = catalog_with_scope("tenant-two")

    assert {:ok, %{"x-scope" => "tenant-one"}} = Catalog.fetch(first, "shared-tool")
    assert {:ok, %{"x-scope" => "tenant-two"}} = Catalog.fetch(second, "shared-tool")
  end

  defp churn_once(index) do
    name = "remote-tool-#{index}"
    schema_revision = "schema-revision-#{index}"

    assert {:ok, catalog} =
             Catalog.new([
               %{
                 "name" => name,
                 "inputSchema" => %{
                   "type" => "object",
                   "x-revision" => schema_revision
                 }
               }
             ])

    assert {:ok, %{"name" => ^name}} = Catalog.fetch(catalog, name)

    assert {:ok, key} =
             ConnectionKey.new(
               integration_id: "integration-#{index}",
               credential_generation: "generation-#{index}"
             )

    assert {:ok, connection} =
             Connections.open(
               key,
               [endpoint: "https://mcp-#{index}.example.test/rpc"],
               runtime: ReadyClientRuntime
             )

    owner_ref = Process.monitor(Connection.owner(connection))
    assert :ok = Connections.close(connection)
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}
    assert :error = Connections.lookup(key)
  end

  defp loaded_modules do
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> MapSet.new()
  end

  defp catalog_with_scope(scope) do
    {:ok, catalog} =
      Catalog.new([
        %{
          "name" => "shared-tool",
          "inputSchema" => %{"type" => "object"},
          "x-scope" => scope
        }
      ])

    catalog
  end
end
