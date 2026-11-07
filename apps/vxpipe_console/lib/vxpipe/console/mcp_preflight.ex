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

  @impl true
  def discover_saved(options, tenant, input, origin, registration, entry) do
    runner = Keyword.get(options, :preflight_runner, Vxpipe.MCP.PreflightRunner)

    Vxpipe.MCP.PreflightRunner.run(runner, tenant, fn ->
      with :ok <- Vxpipe.Calls.MCPDiscoveryProposal.validate(input),
           true <- input["endpoint"] == entry["endpoint"],
           {:ok, client} <- Vxpipe.MCP.ClientMetadata.document(origin),
           {:ok, result} <- Vxpipe.MCP.Preflight.discover(tenant, input, options) do
        choice =
          Vxpipe.Console.MCPListedOAuth.choice(
            entry["authentication"]["registration"],
            result,
            origin,
            registration
          )

        result =
          cond do
            choice ->
              Map.put(result, :oauth_registration, choice)

            result.outcome == :oauth ->
              Map.merge(result, %{outcome: :unsupported_oauth, suggested_method: nil})

            true ->
              result
          end

        [callback] = client.redirect_uris

        {:ok,
         Map.merge(result, %{
           listing: entry,
           oauth_client: %{callback_url: callback, client_id: client.client_id}
         })}
      else
        false -> {:error, :invalid_mcp_preflight}
        error -> error
      end
    end)
  catch
    :exit, _ -> {:error, :mcp_discovery_unavailable}
  end

  defp resolve_listing(%{"listing" => reference} = input, options) do
    with {:ok, snapshot} <- Listing.resolve(reference, Keyword.get(options, :listing_options, [])) do
      {:ok, input |> Map.delete("listing") |> Map.put("endpoint", snapshot["endpoint"]), snapshot}
    end
  end

  defp resolve_listing(input, _options), do: {:ok, input, nil}
end
