defmodule Vxpipe.MCP.CheckProtocolFixture do
  @behaviour Vxpipe.MCP.ProtocolClient
  def list_tools(client, _cursor, _timeout) do
    {:ok, status} = Vxpipe.MCP.ReadyClient.status(client)
    send(status.test_owner, {:checked_client, client})

    case status.test_result do
      :hold ->
        receive do
          :release -> {:ok, %{"tools" => []}}
        end

      result ->
        result
    end
  end

  def call_tool(_client, _name, _arguments, _timeout),
    do: raise("connection checks must never invoke tools")
end
