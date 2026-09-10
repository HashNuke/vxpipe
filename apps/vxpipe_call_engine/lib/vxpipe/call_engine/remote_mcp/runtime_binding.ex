defmodule Vxpipe.CallEngine.RemoteMCP.RuntimeBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.MCP.{Catalog, Connection}

  @enforce_keys [:local_name, :resolved, :catalog, :connection, :protocol]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          local_name: String.t(),
          resolved: ResolvedTool.t(),
          catalog: Catalog.t(),
          connection: Connection.t(),
          protocol: module()
        }
end
