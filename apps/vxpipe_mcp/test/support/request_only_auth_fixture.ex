defmodule Vxpipe.MCP.Test.RequestOnlyAuthFixture do
  @moduledoc false

  defdelegate resolve(context, tenant, id, generation), to: Vxpipe.MCP.Test.RuntimeAuthFixture
end
