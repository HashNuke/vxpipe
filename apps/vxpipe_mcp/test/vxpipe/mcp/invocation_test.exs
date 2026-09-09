defmodule Vxpipe.MCP.InvocationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{Catalog, Invocation, ScriptedProtocolClient}

  test "validates arguments before submitting a catalog tool" do
    client = start_client([{:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}])
    catalog = catalog([order_tool()])

    assert {:error, :invalid_arguments} =
             Invocation.call(client, catalog, "lookup_order", %{"order_id" => 42},
               protocol: ScriptedProtocolClient,
               deadline_ms: 1_000,
               max_result_bytes: 10_000
             )

    assert invocations(client) == []

    arguments = %{"order_id" => "order_123"}

    assert {:ok, %{"content" => [%{"text" => "found", "type" => "text"}]}} =
             Invocation.call(client, catalog, "lookup_order", arguments,
               protocol: ScriptedProtocolClient,
               deadline_ms: 1_000,
               max_result_bytes: 10_000
             )

    assert [%{name: "lookup_order", arguments: ^arguments, timeout: timeout}] =
             invocations(client)

    assert timeout in 1..1_000
  end

  test "rejects unknown tools and external schema references before submission" do
    external_ref_tool = %{
      "name" => "external_ref",
      "inputSchema" => %{"$ref" => "https://schemas.example.test/tool.json"}
    }

    client = start_client([])
    catalog = catalog([order_tool(), external_ref_tool])

    assert {:error, :unknown_tool} =
             Invocation.call(client, catalog, "missing", %{}, protocol: ScriptedProtocolClient)

    assert {:error, :unsupported_input_schema} =
             Invocation.call(client, catalog, "external_ref", %{},
               protocol: ScriptedProtocolClient
             )

    assert invocations(client) == []
  end

  test "validates explicit Draft 7 arguments before submission" do
    client = start_client([{:ok, %{"content" => []}}])

    tool = %{
      "name" => "echo",
      "inputSchema" => %{
        "$schema" => "http://json-schema.org/draft-07/schema#",
        "type" => "object",
        "properties" => %{"message" => %{"type" => "string"}},
        "required" => ["message"]
      }
    }

    assert {:error, :invalid_arguments} =
             Invocation.call(client, catalog([tool]), "echo", %{"message" => 42},
               protocol: ScriptedProtocolClient
             )

    assert invocations(client) == []

    assert {:ok, %{"content" => []}} =
             Invocation.call(client, catalog([tool]), "echo", %{"message" => "hello"},
               protocol: ScriptedProtocolClient
             )

    assert [%{arguments: %{"message" => "hello"}}] = invocations(client)
  end

  test "withholds a decoded result that exceeds the configured byte limit" do
    client = start_client([{:ok, %{"content" => [String.duplicate("x", 100)]}}])

    assert {:error, :result_too_large} =
             Invocation.call(
               client,
               catalog([order_tool()]),
               "lookup_order",
               %{"order_id" => "1"},
               protocol: ScriptedProtocolClient,
               max_result_bytes: 10
             )

    assert length(invocations(client)) == 1
  end

  defp start_client(invocation_responses) do
    start_supervised!(
      {Agent,
       fn ->
         %{
           calls: [],
           responses: [],
           invocation_responses: invocation_responses,
           invocations: []
         }
       end}
    )
  end

  defp invocations(client), do: Agent.get(client, & &1.invocations)

  defp catalog(tools) do
    {:ok, catalog} = Catalog.new(tools)
    catalog
  end

  defp order_tool do
    %{
      "name" => "lookup_order",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{"order_id" => %{"type" => "string"}},
        "required" => ["order_id"],
        "additionalProperties" => false
      }
    }
  end
end
