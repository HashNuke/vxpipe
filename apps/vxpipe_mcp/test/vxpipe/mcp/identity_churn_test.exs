defmodule Vxpipe.MCP.IdentityChurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{Catalog, IdentityProbe}

  @churn_count 250
  @max_runtime_growth 5

  test "integration and catalog churn does not create proportional atoms or modules" do
    assert %{atom_growth: atom_growth, module_growth: module_growth, atomized_values: []} =
             measure_identity_churn()

    assert atom_growth <= @max_runtime_growth
    assert module_growth <= @max_runtime_growth
  end

  test "the same remote name resolves only within the supplied catalog" do
    first = catalog_with_scope("tenant-one")
    second = catalog_with_scope("tenant-two")

    assert {:ok, %{"x-scope" => "tenant-one"}} = Catalog.fetch(first, "shared-tool")
    assert {:ok, %{"x-scope" => "tenant-two"}} = Catalog.fetch(second, "shared-tool")
  end

  defp measure_identity_churn do
    args = [~c"-pa" | :code.get_path()]
    {:ok, peer, _node} = :peer.start_link(%{connection: :standard_io, args: args})

    try do
      _startup_measurement =
        :peer.call(peer, IdentityProbe, :measure, [@churn_count, 0], 30_000)

      :peer.call(
        peer,
        IdentityProbe,
        :measure,
        [@churn_count, 2 * @churn_count],
        30_000
      )
    after
      :peer.stop(peer)
    end
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
