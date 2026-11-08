defmodule Vxpipe.MCP.Test.RequestOnlyProvider do
  @moduledoc false
  defdelegate init(config), to: Vxpipe.MCP.RuntimeAuthProvider
  defdelegate get_headers(state), to: Vxpipe.MCP.RuntimeAuthProvider
end
