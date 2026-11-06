defmodule Vxpipe.Calls.MCPTransportCredentials do
  @moduledoc "Projects current saved credentials into the MCP runtime provider contract."

  alias Vxpipe.Calls.MCPRuntimeCredentials

  def resolve(options, tenant, id, generation) do
    with {:ok, saved} <- MCPRuntimeCredentials.resolve(tenant, id, generation, options) do
      case saved.connection.auth_method do
        "oauth" -> {:ok, %{auth_method: "oauth", token: saved.secrets["access_token"]}}
        method -> {:ok, %{auth_method: method}}
      end
    end
  end
end
