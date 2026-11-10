defmodule Vxpipe.Console.IntegrationsDirectory.PageTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.{Page, Request}

  @examples Path.expand("../../../../../../docs/assets/integrations", __DIR__)

  test "rejects unavailable adapters and incompatible rows without changing server pagination" do
    page =
      @examples
      |> Path.join("integrations-directory.search.example.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, request} =
      Request.build(:integrations, %{"q" => "google", "limit" => page["pagination"]["limit"]})

    [provider | rest] = page["items"]

    for invalid_provider <- [
          put_in(provider, ["connection", "provider_id"], "not-installed"),
          Map.put(provider, "minimum_vxpipe_version", "99.0.0"),
          Map.put(provider, "maximum_vxpipe_version_exclusive", Request.installation_version())
        ] do
      assert {:error, :invalid_page} =
               Page.validate(Map.put(page, "items", [invalid_provider | rest]), request)
    end
  end

  test "validates published category and integration examples" do
    for {name, resource} <- [
          {"integrations-directory.example.json", :integrations},
          {"integrations-directory.categories.example.json", :categories},
          {"integrations-directory.search.example.json", :integrations}
        ] do
      page = @examples |> Path.join(name) |> File.read!() |> JSON.decode!()
      params = Map.get(page, "query", %{}) |> Map.reject(fn {_key, value} -> is_nil(value) end)
      params = Map.put(params, "limit", page["pagination"]["limit"])
      {:ok, request} = Request.build(resource, params)
      assert {:ok, ^page} = Page.validate(page, request)
    end
  end

  test "rejects malformed, wrong-version and cross-query responses" do
    page =
      @examples
      |> Path.join("integrations-directory.categories.example.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, request} = Request.build(:categories, %{"limit" => page["pagination"]["limit"]})

    for invalid <- [
          Map.put(page, "schema_version", 2),
          Map.put(page, "installation_version", "99.0.0"),
          Map.put(page, "items", [%{"id" => "connected"}]),
          Map.update!(page, "items", &(&1 ++ &1)),
          put_in(page, ["pagination", "total_items"], -1),
          put_in(page, ["pagination", "end_index"], 99),
          Map.delete(page, "revision")
        ] do
      assert {:error, :invalid_page} = Page.validate(invalid, request)
    end

    {:ok, other_request} = Request.build(:integrations, %{"q" => "another query"})
    assert {:error, :invalid_page} = Page.validate(page, other_request)
  end

  test "an explicitly requested snapshot must match the returned revision" do
    for {name, resource} <- [
          {"integrations-directory.categories.example.json", :categories},
          {"integrations-directory.search.example.json", :integrations}
        ] do
      page = @examples |> Path.join(name) |> File.read!() |> JSON.decode!()
      params = Map.get(page, "query", %{}) |> Map.reject(fn {_key, value} -> is_nil(value) end)

      params =
        Map.merge(params, %{
          "limit" => page["pagination"]["limit"],
          "revision" => "another-snapshot"
        })

      {:ok, request} = Request.build(resource, params)
      assert {:error, :invalid_page} = Page.validate(page, request)

      {:ok, matching_request} =
        Request.build(resource, Map.put(params, "revision", page["revision"]))

      assert {:ok, ^page} = Page.validate(page, matching_request)
    end
  end

  test "a request without a cursor cannot accept a later page" do
    page =
      @examples
      |> Path.join("integrations-directory.categories.example.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.update!(
        "pagination",
        &Map.merge(&1, %{
          "start_index" => 2,
          "end_index" => 2,
          "total_items" => 2,
          "previous_cursor" => "previous-page"
        })
      )

    params = %{"limit" => page["pagination"]["limit"]}
    {:ok, request} = Request.build(:categories, params)
    assert {:error, :invalid_page} = Page.validate(page, request)

    {:ok, continuation} = Request.build(:categories, Map.put(params, "cursor", "second-page"))
    assert {:ok, ^page} = Page.validate(page, continuation)
  end

  test "URL fields must satisfy URI format in addition to their HTTPS prefix" do
    page =
      @examples
      |> Path.join("integrations-directory.search.example.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, request} = Request.build(:integrations, %{"q" => "google"})
    [provider, mcp] = page["items"]

    for invalid <- [
          put_in(mcp, ["connection", "endpoint"], "https://not a host/mcp"),
          Map.put(mcp, "documentation_url", "https://not a host"),
          Map.put(mcp, "logo_url", "https://not a host/logo.png"),
          Map.put(mcp, "setup_url", "https://not a host/setup")
        ] do
      assert {:error, :invalid_page} =
               Page.validate(Map.put(page, "items", [provider, invalid]), request)
    end
  end

  test "MCP endpoints require a host and a valid network port" do
    page =
      @examples
      |> Path.join("integrations-directory.search.example.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, request} = Request.build(:integrations, %{"q" => "google"})
    [provider, mcp] = page["items"]

    for endpoint <- [
          "https://:443/mcp",
          "https://server.example:65536/mcp",
          "https://server.example:0/mcp"
        ] do
      invalid = put_in(mcp, ["connection", "endpoint"], endpoint)

      assert {:error, :invalid_page} =
               Page.validate(Map.put(page, "items", [provider, invalid]), request)
    end
  end
end
