defmodule Vxpipe.Calls.MCPSavedPreflight do
  @moduledoc "Generation-bound advisory discovery of accepted listed OAuth configuration."
  alias Vxpipe.Calls.{MCPDiscoveryProposal, MCPSavedOAuthRegistration, Repositories}

  @public_fields ~w(endpoint revision suggested_method outcome reason resource issuers oauth supported_grants listing oauth_registration oauth_client server_name)a

  # MCPConnections owns current tenant write authority before and after this operation.
  def discover(probe, tenant, input, options) do
    with :ok <- supported(probe),
         {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, connection} <- target(repository, tenant, input),
         {:ok, identity} <- installation(options),
         {:ok, registration} <- MCPSavedOAuthRegistration.fetch(repository, tenant, connection),
         canonical =
           input |> Map.take(~w(revision issuer)) |> Map.put("endpoint", connection.endpoint),
         {:ok, result} <-
           Repositories.call(probe, :discover_saved, [
             tenant,
             canonical,
             identity.origin,
             registration,
             connection.directory_entry
           ]),
         :ok <- matches(result, canonical, connection.directory_entry),
         {:ok, current} <- target(repository, tenant, input),
         :ok <- unchanged(connection, current),
         {:ok, latest_identity} <- installation(options),
         :ok <- same_installation(identity, latest_identity) do
      {:ok,
       result
       |> Map.take(@public_fields)
       |> Map.merge(%{connection_id: connection.id, generation: connection.generation})}
    end
  end

  defp supported({module, _context}) do
    if Code.ensure_loaded?(module) and function_exported?(module, :discover_saved, 6),
      do: :ok,
      else: {:error, :mcp_discovery_unavailable}
  end

  defp target(repository, tenant, %{"connection_id" => id, "generation" => generation}) do
    with {:ok, connection} <- Repositories.call(repository, :get_retained, [tenant, id]) do
      cond do
        connection.id != id or connection.tenant_key != tenant ->
          {:error, :mcp_connection_not_found}

        connection.generation != generation ->
          {:error, :stale_mcp_connection}

        connection.status not in ~w(connected revoked) or connection.auth_method != "oauth" ->
          {:error, :invalid_mcp_preflight}

        not match?(
          %{"authentication" => %{"type" => "oauth2"}},
          Map.get(connection, :directory_entry)
        ) ->
          {:error, :invalid_mcp_preflight}

        true ->
          {:ok, connection}
      end
    end
  end

  defp matches(result, input, entry) do
    if is_map(result) and MCPDiscoveryProposal.matches?(result, input) and
         Map.get(result, :listing) == entry, do: :ok, else: {:error, :mcp_discovery_unavailable}
  end

  defp unchanged(saved, current) do
    fields = [:id, :tenant_key, :generation, :status, :endpoint, :auth_method, :directory_entry]

    if Map.take(saved, fields) == Map.take(current, fields),
      do: :ok,
      else: {:error, :stale_mcp_connection}
  end

  defp installation(options) do
    case Keyword.get(options, :installation_identity) do
      callback when is_function(callback, 0) ->
        case callback.() do
          {:ok, %{origin: origin, revision: revision} = identity}
          when is_binary(origin) and is_integer(revision) and revision >= 0 ->
            {:ok, identity}

          _ ->
            {:error, :mcp_installation_unavailable}
        end

      _ ->
        {:error, :mcp_installation_unavailable}
    end
  end

  defp same_installation(identity, identity), do: :ok
  defp same_installation(_, _), do: {:error, :mcp_installation_changed}
end
