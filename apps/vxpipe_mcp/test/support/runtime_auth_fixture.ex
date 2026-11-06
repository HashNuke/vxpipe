defmodule Vxpipe.MCP.Test.RuntimeAuthFixture do
  def resolve({owner, result}, tenant, id, generation) do
    send(owner, {:resolved, tenant, id, generation})
    result = if is_function(result, 0), do: result.(), else: result

    case result do
      {:ok, data} -> {:ok, Map.put_new(data, :endpoint, "https://mcp.example.test/mcp")}
      error -> error
    end
  end
end
