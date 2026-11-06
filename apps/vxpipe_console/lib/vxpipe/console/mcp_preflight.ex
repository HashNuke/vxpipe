defmodule Vxpipe.Console.MCPPreflight do
  @moduledoc "Composes the bounded credentialless MCP discovery port."
  @behaviour Vxpipe.Calls.MCPPreflight
  alias Vxpipe.Console.IntegrationsDirectory.Listing
  @impl true
  def discover(options, tenant, input) do
    runner = Keyword.get(options, :preflight_runner, Vxpipe.MCP.PreflightRunner)

    Vxpipe.MCP.PreflightRunner.run(runner, tenant, fn ->
      with :ok <- Vxpipe.Calls.MCPDiscoveryProposal.validate(input),
           {:ok, input, listing} <- resolve_listing(input, options),
           {:ok, result} <- Vxpipe.MCP.Preflight.discover(tenant, input, options) do
        {:ok, if(listing, do: Map.put(result, :listing, listing), else: result)}
      end
    end)
  catch
    :exit, _reason -> {:error, :mcp_discovery_unavailable}
  end

  defp resolve_listing(%{"listing" => reference} = input, options) do
    with {:ok, snapshot} <- Listing.resolve(reference, Keyword.get(options, :listing_options, [])) do
      {:ok, input |> Map.delete("listing") |> Map.put("endpoint", snapshot["endpoint"]), snapshot}
    end
  end

  defp resolve_listing(input, _options), do: {:ok, input, nil}
end
