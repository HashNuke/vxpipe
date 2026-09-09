defmodule Vxpipe.MCP.ReferenceProbeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{ReferenceProbe, ScriptedProtocolClient}

  test "discovers and invokes the reference echo tool as data" do
    client =
      start_supervised!(
        {Agent,
         fn ->
           %{
             responses: [
               {:ok,
                %{
                  "tools" => [
                    %{
                      "name" => "echo",
                      "description" => "Echoes back the input",
                      "inputSchema" => %{
                        "$schema" => "http://json-schema.org/draft-07/schema#",
                        "type" => "object",
                        "properties" => %{"message" => %{"type" => "string"}},
                        "required" => ["message"]
                      }
                    }
                  ]
                }}
             ],
             calls: [],
             invocation_responses: [
               {:ok,
                %{
                  "content" => [
                    %{"type" => "text", "text" => "Echo: vxpipe-reference-probe"}
                  ]
                }}
             ],
             invocations: []
           }
         end}
      )

    assert {:ok, %{tool: tool, result: result}} =
             ReferenceProbe.run(client, protocol: ScriptedProtocolClient)

    assert tool["name"] == "echo"

    assert result == %{
             "content" => [
               %{"type" => "text", "text" => "Echo: vxpipe-reference-probe"}
             ]
           }

    assert %{invocations: [invocation]} = Agent.get(client, & &1)
    assert invocation.name == "echo"
    assert invocation.arguments == %{"message" => "vxpipe-reference-probe"}
  end
end
