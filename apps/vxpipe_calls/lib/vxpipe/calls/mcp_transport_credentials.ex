defmodule Vxpipe.Calls.MCPTransportCredentials do
  @moduledoc "Projects current saved credentials into the MCP runtime provider contract."

  alias Vxpipe.Calls.MCPRuntimeCredentials
  alias Vxpipe.MCP.{Authentication, StaticConfiguration}

  def resolve(:configured, tenant, id, generation), do: resolve([], tenant, id, generation)

  def resolve(options, tenant, id, generation) do
    project(MCPRuntimeCredentials.resolve(tenant, id, generation, options))
  end

  def resolve_cleanup(:configured, tenant, id, generation),
    do: resolve_cleanup([], tenant, id, generation)

  def resolve_cleanup(options, tenant, id, generation) do
    project(MCPRuntimeCredentials.resolve_cleanup(tenant, id, generation, options))
  end

  defp project(resolved) do
    with {:ok, saved} <- resolved,
         {:ok, configuration} <- StaticConfiguration.new(input(saved)),
         {:ok, headers} <- Authentication.headers(configuration.authentication) do
      result = %{
        auth_method: saved.connection.auth_method,
        endpoint: configuration.endpoint,
        headers: headers
      }

      {:ok,
       if(saved.connection.auth_method == "oauth",
         do: Map.put(result, :token, saved.secrets["access_token"]),
         else: result
       )}
    end
  end

  defp input(%{connection: %{auth_method: "oauth"}} = saved),
    do: %{
      "endpoint" => saved.connection.endpoint,
      "auth_method" => "bearer",
      "credentials" => %{
        "token" => saved.secrets["access_token"],
        "headers" => Map.get(saved.secrets, "headers", [])
      }
    }

  defp input(saved),
    do: %{
      "endpoint" => saved.connection.endpoint,
      "auth_method" => saved.connection.auth_method,
      "credentials" => saved.secrets
    }
end
