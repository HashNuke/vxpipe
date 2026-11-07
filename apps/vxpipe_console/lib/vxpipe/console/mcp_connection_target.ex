defmodule Vxpipe.Console.MCPConnectionTarget do
  @moduledoc "Resolves public connection identity without MCP discovery, credentials or OAuth side effects."
  alias Vxpipe.Console.IntegrationsDirectory.Listing
  alias Vxpipe.MCP.StaticConfiguration

  def resolve(options, _tenant, input) do
    with :ok <- issuer(input),
         {:ok, endpoint, entry} <- endpoint(options, input) do
      {:ok,
       %{
         endpoint: endpoint,
         endpoint_identity: endpoint,
         directory_entry: entry,
         directory_id: if(entry, do: entry["directory_id"] <> "/" <> entry["integration_id"]),
         revision: input["revision"]
       }}
    end
  end

  defp endpoint(options, %{"listing" => reference}) do
    with {:ok, entry} <- Listing.resolve(reference, Keyword.get(options, :listing_options, [])),
         do: {:ok, entry["endpoint"], entry}
  end

  defp endpoint(_options, %{"endpoint" => value}) do
    with {:ok, endpoint} <- StaticConfiguration.endpoint(value), do: {:ok, endpoint, nil}
  end

  defp endpoint(_, _), do: {:error, :invalid_mcp_endpoint}

  defp issuer(%{"issuer" => issuer}) do
    with {:ok, _} <- StaticConfiguration.endpoint(issuer),
         {:ok, %URI{query: nil}} <- URI.new(issuer),
         do: :ok,
         else: (_ -> {:error, :invalid_oauth_issuer})
  end

  defp issuer(_), do: :ok
end
