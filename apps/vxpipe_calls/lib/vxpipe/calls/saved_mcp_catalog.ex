defmodule Vxpipe.Calls.SavedMCPCatalog do
  @moduledoc "Secret-free cached tool choices from tenant-owned saved MCP connections."
  alias Vxpipe.Calls.Repositories

  def names(tenant, options) do
    case records(tenant, options) do
      {:ok, records} -> {:ok, records |> Enum.map(& &1.id) |> Enum.uniq() |> Enum.sort()}
      {:error, _} -> {:ok, []}
    end
  end

  def tools(tenant, options) do
    with {:ok, records} <- records(tenant, options),
         do: {:ok, records |> Enum.flat_map(&tools/1) |> Enum.sort_by(&{&1.integration, &1.tool})}
  end

  @doc false
  def records(tenant, options) do
    with {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, records} when is_list(records) <- Repositories.call(repository, :list, [tenant]),
         true <- Enum.all?(records, &valid_record?(&1, tenant)) do
      {:ok, records}
    else
      _ -> {:error, :mcp_catalog_unavailable}
    end
  rescue
    _ -> {:error, :mcp_catalog_unavailable}
  catch
    :exit, _ -> {:error, :mcp_catalog_unavailable}
  end

  defp valid_record?(
         %{
           id: id,
           tenant_key: tenant,
           generation: generation,
           status: "connected",
           catalog: catalog
         },
         tenant
       )
       when is_binary(id) and byte_size(id) in 1..128 and is_integer(generation) and
              generation > 0 and is_list(catalog) do
    Enum.all?(catalog, &valid_tool?/1) and
      length(Enum.uniq_by(catalog, & &1["name"])) == length(catalog)
  end

  defp valid_record?(_, _), do: false

  defp valid_tool?(%{"name" => name, "inputSchema" => schema} = tool)
       when is_binary(name) and byte_size(name) in 1..128 and is_map(schema),
       do: is_binary(Map.get(tool, "description", ""))

  defp valid_tool?(_), do: false

  defp tools(record),
    do:
      record.catalog
      |> Enum.filter(&(Vxpipe.MCP.ArgumentValidator.validate_schema(&1["inputSchema"]) == :ok))
      |> Enum.map(fn tool ->
        %{
          type: "mcp",
          integration: record.id,
          tool: tool["name"],
          description: Map.get(tool, "description", "")
        }
      end)
end
