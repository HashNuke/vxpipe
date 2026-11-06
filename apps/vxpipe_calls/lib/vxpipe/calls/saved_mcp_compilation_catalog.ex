defmodule Vxpipe.Calls.SavedMCPCompilationCatalog do
  @moduledoc "Builds tenant-only compilation snapshots from cached metadata without loading credentials."

  alias Vxpipe.CallEngine.RemoteMCP.{Integration, IntegrationCatalog}
  alias Vxpipe.Calls.SavedMCPCatalog
  alias Vxpipe.MCP.Catalog

  def build(tenant, options) do
    with {:ok, records} <- SavedMCPCatalog.records(tenant, options),
         true <- length(Enum.uniq_by(records, & &1.id)) == length(records),
         {:ok, integrations} <- integrations(records),
         {:ok, catalog} <- IntegrationCatalog.new(tenants: %{tenant => integrations}) do
      {:ok, catalog}
    else
      _ -> {:error, :mcp_catalog_unavailable}
    end
  end

  defp integrations(records) do
    records
    |> Enum.reject(&(&1.catalog == []))
    |> Enum.reduce_while({:ok, %{}}, fn record, {:ok, acc} ->
      case integration(record) do
        {:ok, integration} -> {:cont, {:ok, Map.put(acc, record.id, integration)}}
        error -> {:halt, error}
      end
    end)
  end

  @doc false
  def integration(record) do
    with {:ok, catalog} <- Catalog.new(record.catalog) do
      generation = Integer.to_string(record.generation)

      Integration.new(
        integration_id: record.id,
        configuration_generation: generation,
        credential_generation: generation,
        catalog_generation: catalog_generation(record.catalog),
        catalog: catalog,
        allowed_tools: Enum.map(record.catalog, & &1["name"]),
        client_config: []
      )
    end
  end

  defp catalog_generation(tools) do
    tools
    |> Enum.sort_by(& &1["name"])
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
