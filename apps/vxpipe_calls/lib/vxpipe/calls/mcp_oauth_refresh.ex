defmodule Vxpipe.Calls.MCPOAuthRefresh do
  @moduledoc "Trusted runtime refresh coordination; caller owns authorization to use the tenant connection."
  alias Vxpipe.Calls.Repositories

  def refresh(tenant, id, generation, revision, options \\ []) do
    with {:ok, repository} <- Repositories.fetch(options, :mcp_oauth_grant_repository),
         {:ok, protocol} <- Repositories.fetch(options, :mcp_oauth_refresh) do
      session = Keyword.get(options, :mcp_session)

      operation = fn ->
        case Repositories.call(repository, :claim, [tenant, id, generation, revision]) do
          {:ok, claim} -> {:admitted, {:claimed, claim.id, exchange(protocol, claim, session)}}
          error -> {:admitted, error}
        end
      end

      case run(protocol, tenant, operation, session) do
        {:admitted, {:claimed, claim_id, result}} ->
          finish(repository, [tenant, id, generation, claim_id], result)

        {:admitted, {:error, _} = error} ->
          error

        {:error, reason} when reason in [:mcp_connection_busy, :mcp_connection_timed_out] ->
          {:error, reason}

        _ ->
          {:error, :oauth_reconnect_required}
      end
    end
  end

  defp run(protocol, tenant, operation, nil),
    do: Repositories.call(protocol, :run, [tenant, operation])

  defp run(protocol, tenant, operation, session),
    do: Repositories.call(protocol, :run_owned, [tenant, operation, session])

  defp finish(repository, identity, exchanged) do
    result =
      case exchanged do
        {:ok, tokens} when is_map(tokens) ->
          Repositories.call(repository, :complete, identity ++ [tokens])

        _ ->
          {:error, :oauth_reconnect_required}
      end

    case result do
      :ok ->
        :ok

      _ ->
        _ = Repositories.call(repository, :fail, identity)
        {:error, :oauth_reconnect_required}
    end
  end

  defp exchange(protocol, claim, session) do
    if session,
      do: Repositories.call(protocol, :refresh_owned, [claim, session]),
      else: Repositories.call(protocol, :refresh, [claim])
  rescue
    _ -> {:error, :oauth_reconnect_required}
  catch
    _, _ -> {:error, :oauth_reconnect_required}
  end
end
