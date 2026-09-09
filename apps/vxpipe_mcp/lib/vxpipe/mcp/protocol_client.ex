defmodule Vxpipe.MCP.ProtocolClient do
  @moduledoc false

  @callback list_tools(client :: term(), cursor :: String.t() | nil, timeout :: pos_integer()) ::
              {:ok, map()} | {:error, term()}

  @callback call_tool(
              client :: term(),
              name :: String.t(),
              arguments :: map(),
              timeout :: pos_integer()
            ) ::
              {:ok, map()}
              | {:error, :not_submitted | :outcome_unknown | :remote_error}
end
