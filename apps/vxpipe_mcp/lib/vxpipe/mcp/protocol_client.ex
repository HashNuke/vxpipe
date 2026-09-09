defmodule Vxpipe.MCP.ProtocolClient do
  @moduledoc false

  @callback list_tools(client :: term(), cursor :: String.t() | nil, timeout :: pos_integer()) ::
              {:ok, map()} | {:error, term()}
end
