defmodule Vxpipe.MCP.Test.RuntimeAuthFixture do
  def resolve({owner, result}, tenant, id, generation) do
    send(owner, {:resolved, tenant, id, generation})
    if is_function(result, 0), do: result.(), else: result
  end
end
