defmodule Vxpipe.MCP.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{Catalog, Discovery, ScriptedProtocolClient}

  test "collects every page while preserving remote definitions as data" do
    first_tool = %{
      "name" => "lookup_order",
      "description" => "Find an order",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"order_id" => %{"type" => "string"}}
      }
    }

    second_tool = %{
      "name" => "request_refund",
      "inputSchema" => %{"type" => "object"},
      "x-remote-extension" => %{"revision" => "tenant-data"}
    }

    client =
      start_client([
        {:ok, %{"tools" => [first_tool], "nextCursor" => "page-2"}},
        {:ok, %{"tools" => [second_tool]}}
      ])

    assert {:ok, %Catalog{} = catalog} =
             Discovery.discover(client,
               protocol: ScriptedProtocolClient,
               deadline_ms: 1_000,
               max_pages: 3,
               max_decoded_bytes: 10_000
             )

    assert Catalog.tools(catalog) == [first_tool, second_tool]
    assert {:ok, ^second_tool} = Catalog.fetch(catalog, "request_refund")
    assert {:error, :unknown_tool} = Catalog.fetch(catalog, "missing")

    assert [%{cursor: nil, timeout: first_timeout}, %{cursor: "page-2", timeout: next_timeout}] =
             calls(client)

    assert first_timeout in 1..1_000
    assert next_timeout in 1..first_timeout
  end

  test "rejects a repeated cursor without publishing a partial catalog" do
    client =
      start_client([
        {:ok, %{"tools" => [tool("first")], "nextCursor" => "again"}},
        {:ok, %{"tools" => [tool("second")], "nextCursor" => "again"}}
      ])

    assert {:error, :repeated_cursor} =
             Discovery.discover(client,
               protocol: ScriptedProtocolClient,
               deadline_ms: 1_000,
               max_pages: 3,
               max_decoded_bytes: 10_000
             )

    assert length(calls(client)) == 2
  end

  test "rejects an operation that exceeds its aggregate decoded-byte budget" do
    first_page = %{"tools" => [tool("first")], "nextCursor" => "next"}
    second_page = %{"tools" => [tool("second")]}
    client = start_client([{:ok, first_page}, {:ok, second_page}])

    assert {:error, :discovery_too_large} =
             Discovery.discover(client,
               protocol: ScriptedProtocolClient,
               deadline_ms: 1_000,
               max_pages: 2,
               max_decoded_bytes: byte_size(Jason.encode!(first_page))
             )

    assert length(calls(client)) == 2
  end

  test "stops endless unique cursors at the page limit" do
    client =
      start_client([
        {:ok, %{"tools" => [tool("first")], "nextCursor" => "second"}},
        {:ok, %{"tools" => [tool("second")], "nextCursor" => "third"}},
        {:ok, %{"tools" => [tool("must-not-be-requested")]}}
      ])

    assert {:error, :discovery_page_limit_exceeded} =
             Discovery.discover(client,
               protocol: ScriptedProtocolClient,
               deadline_ms: 1_000,
               max_pages: 2,
               max_decoded_bytes: 10_000
             )

    assert length(calls(client)) == 2
  end

  test "rejects malformed pages and duplicate identities without a partial catalog" do
    malformed_client = start_client([{:ok, %{"tools" => %{"name" => "not-a-list"}}}])

    assert {:error, :invalid_discovery_response} =
             Discovery.discover(malformed_client, protocol: ScriptedProtocolClient)

    duplicate_client =
      start_client([
        {:ok, %{"tools" => [tool("duplicate")], "nextCursor" => "next"}},
        {:ok, %{"tools" => [tool("duplicate")]}}
      ])

    assert {:error, :duplicate_tool_name} =
             Discovery.discover(duplicate_client, protocol: ScriptedProtocolClient)
  end

  test "does not expose protocol diagnostics" do
    client = start_client([{:error, "authorization: Bearer private-secret"}])

    result = Discovery.discover(client, protocol: ScriptedProtocolClient)

    assert result == {:error, :discovery_failed}
    refute inspect(result) =~ "private-secret"
  end

  defp start_client(responses) do
    start_supervised!(
      {Agent, fn -> %{calls: [], responses: responses} end},
      id: {Agent, make_ref()}
    )
  end

  defp calls(client), do: Agent.get(client, & &1.calls)

  defp tool(name) do
    %{"name" => name, "inputSchema" => %{"type" => "object"}}
  end
end
