defmodule Vxpipe.Console.IntegrationsDirectory.ClientTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.{Client, Request}

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  test "returns a validated empty page and a cache validator" do
    Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, empty_page()) end)

    assert {:ok, %{body: %{"items" => []}, etag: nil}} = fetch()
  end

  test "rejects mismatched query and unsupported schema instead of rendering them" do
    for page <- [
          Map.put(empty_page(), "schema_version", 2),
          put_in(empty_page(), ["query", "scope"], "platform")
        ] do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, page) end)
      assert {:error, :invalid_page} = fetch()
    end
  end

  test "invalid input fails before performing HTTP" do
    assert {:error, :invalid_query} = Client.fetch(:integrations, %{"tenant_id" => "private"})
  end

  defp fetch do
    Client.fetch(:integrations, %{}, plug: {Req.Test, __MODULE__})
  end

  defp empty_page do
    %{
      "schema_version" => 1,
      "directory_id" => "example",
      "revision" => "revision",
      "resource" => "integrations",
      "installation_version" => Request.installation_version(),
      "query" => %{"q" => "", "category" => nil, "scope" => "tenant"},
      "items" => [],
      "pagination" => %{
        "limit" => 20,
        "total_items" => 0,
        "start_index" => 0,
        "end_index" => 0,
        "next_cursor" => nil,
        "previous_cursor" => nil
      }
    }
  end
end
