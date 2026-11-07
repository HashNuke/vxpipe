defmodule Vxpipe.Console.MCPListedConnection do
  @moduledoc "Projects accepted listing recipes into the existing static MCP connection probe."

  alias Vxpipe.Console.{IntegrationsDirectory.Listing, MCPConnectionProbe}
  alias Vxpipe.MCP.PreflightRunner

  def check(options, tenant, input) do
    with :ok <- input(input, ~w(listing endpoint auth_method credentials)) do
      runner = Keyword.get(options, :preflight_runner, PreflightRunner)

      PreflightRunner.run(runner, tenant, fn ->
        with {:ok, entry} <-
               Listing.resolve(input["listing"], Keyword.get(options, :listing_options, [])) do
          probe(options, tenant, input["credentials"], entry)
        end
      end)
    end
  catch
    :exit, _ -> {:error, :mcp_connection_failed}
  end

  def check_saved(options, tenant, input, entry) do
    with :ok <- input(input, ~w(endpoint auth_method credentials)) do
      probe(options, tenant, input["credentials"], entry)
    end
  end

  defp probe(options, tenant, credentials, entry) do
    with {:ok, method, credentials} <- credentials(entry["authentication"], credentials),
         {:ok, resolved} <-
           MCPConnectionProbe.check(options, tenant, %{
             "endpoint" => entry["endpoint"],
             "auth_method" => method,
             "credentials" => credentials
           }) do
      {:ok,
       %{
         resolved
         | connection:
             Map.merge(resolved.connection, %{
               directory_id: entry["directory_id"] <> "/" <> entry["integration_id"],
               directory_entry: entry,
               server_name: entry["name"]
             })
       }}
    end
  end

  defp input(%{"credentials" => credentials} = input, allowed) when is_map(credentials) do
    if Map.keys(input) -- allowed == [] and byte_size(JSON.encode!(input)) <= 73_728,
      do: :ok,
      else: {:error, :invalid_mcp_configuration}
  rescue
    _ -> {:error, :invalid_mcp_configuration}
  end

  defp input(_input, _allowed), do: {:error, :invalid_mcp_configuration}

  defp credentials(%{"type" => "none"}, credentials) when credentials == %{},
    do: {:ok, "none", %{}}

  defp credentials(%{"type" => "bearer"}, %{"token" => token} = credentials)
       when map_size(credentials) == 1,
       do: {:ok, "bearer", %{"token" => token}}

  defp credentials(%{"type" => "basic"}, %{"username" => _, "password" => _} = credentials)
       when map_size(credentials) == 2,
       do: {:ok, "basic", credentials}

  defp credentials(
         %{"type" => "api_key", "header_name" => name},
         %{"headers" => [%{"value" => value} = header]} = credentials
       )
       when map_size(credentials) == 1 do
    if Map.keys(header) -- ~w(name value) == [],
      do: {:ok, "headers", %{"headers" => [%{"name" => name, "value" => value}]}},
      else: {:error, :invalid_mcp_configuration}
  end

  defp credentials(_recipe, _credentials), do: {:error, :invalid_mcp_configuration}
end
