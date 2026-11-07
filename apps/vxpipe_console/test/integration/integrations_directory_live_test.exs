defmodule Vxpipe.Console.IntegrationsDirectoryLiveTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.IntegrationsDirectory.{Client, NativeCatalog}

  @moduletag :live_integrations_directory

  @tag timeout: 120_000
  test "the hosted release serves installed native adapters and tenant-only MCPs" do
    {tenant, revision} = fetch_all(:integrations, %{"scope" => "tenant"})
    {categories, ^revision} = fetch_all(:categories, %{"revision" => revision})

    {platform, ^revision} =
      fetch_all(:integrations, %{"scope" => "platform", "revision" => revision})

    installed = NativeCatalog.items()
    expected = provider_ids(installed)

    assert provider_ids(tenant) == expected,
           "hosted tenant catalog is missing this release's native adapters"

    assert provider_ids(platform) == expected
    assert Enum.all?(platform, &(&1["kind"] == "provider"))

    mcps = Enum.filter(tenant, &(&1["kind"] == "mcp"))
    assert mcps != [], "hosted tenant catalog must include MCP entries"

    category_ids = MapSet.new(categories, & &1["id"])
    mcp_categories = mcps |> Enum.flat_map(& &1["category_ids"]) |> MapSet.new()
    assert MapSet.subset?(mcp_categories, category_ids)
    assert MapSet.disjoint?(category_ids, MapSet.new(~w(connected ai telephony search)))

    for category <- ~w(ai telephony) do
      {items, ^revision} =
        fetch_all(:integrations, %{"category" => category, "revision" => revision})

      expected_category = Enum.filter(installed, &(category in &1["category_ids"]))
      assert provider_ids(items) == provider_ids(expected_category)
      assert Enum.all?(items, &(&1["kind"] == "provider"))
    end

    {search, ^revision} =
      fetch_all(:integrations, %{"q" => "GoOgLe", "revision" => revision})

    assert MapSet.new(search, & &1["kind"]) == MapSet.new(~w(provider mcp))
  end

  defp provider_ids(items) do
    items
    |> Enum.filter(&(&1["kind"] == "provider"))
    |> MapSet.new(& &1["connection"]["provider_id"])
  end

  defp fetch_all(resource, params) do
    params = Map.put(params, "limit", 100)
    assert {:ok, %{body: page}} = Client.fetch(resource, params)
    items = collect_pages(resource, params, page, 10)
    assert length(items) == page["pagination"]["total_items"]
    assert MapSet.size(MapSet.new(items, & &1["id"])) == length(items)
    {items, page["revision"]}
  end

  defp collect_pages(resource, params, page, remaining) do
    case page["pagination"]["next_cursor"] do
      nil ->
        page["items"]

      cursor ->
        assert remaining > 1, "hosted catalog acceptance exceeded its ten-page bound"
        params = Map.merge(params, %{"cursor" => cursor, "revision" => page["revision"]})
        assert {:ok, %{body: next}} = Client.fetch(resource, params)
        assert next["pagination"]["start_index"] == page["pagination"]["end_index"] + 1
        assert next["pagination"]["total_items"] == page["pagination"]["total_items"]
        page["items"] ++ collect_pages(resource, params, next, remaining - 1)
    end
  end
end
