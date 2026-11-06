defmodule Vxpipe.Calls.MCPRuntimeCredentials do
  @moduledoc "Trusted runtime credential resolution pinned to tenant, connection and configuration generation."
  alias Vxpipe.Calls.{MCPOAuthRefresh, Repositories, ResolvedMCPConnection}

  def resolve(tenant, id, generation, options \\ []),
    do: resolve(tenant, id, generation, options, true)

  defp resolve(tenant, id, generation, options, refresh?) do
    with {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
         {:ok, %ResolvedMCPConnection{connection: connection} = saved} <-
           Repositories.call(repository, :resolve, [tenant, id]),
         true <-
           connection.tenant_key == tenant and connection.id == id and
             connection.generation == generation and connection.status == "connected" do
      credentials(saved, tenant, id, generation, options, refresh?)
    else
      _ -> {:error, :mcp_connection_unavailable}
    end
  end

  defp credentials(
         %ResolvedMCPConnection{connection: %{auth_method: "oauth"}, secrets: secrets} = saved,
         tenant,
         id,
         generation,
         options,
         refresh?
       ) do
    now = Keyword.get(options, :now, &DateTime.utc_now/0).()

    with :ok <- refresh_state(secrets["refresh_claim"], now),
         {:ok, expiry} <- expiry(secrets["expires_at"]),
         token when is_binary(token) and byte_size(token) > 0 <- secrets["access_token"] do
      margin = if refresh?, do: 30, else: 0

      if is_nil(expiry) or DateTime.diff(expiry, now) > margin do
        {:ok, %{saved | secrets: %{"access_token" => token}}}
      else
        if refresh? do
          with :ok <-
                 MCPOAuthRefresh.refresh(
                   tenant,
                   id,
                   generation,
                   Map.get(secrets, "grant_revision", 1),
                   options
                 ),
               do: resolve(tenant, id, generation, options, false)
        else
          {:error, :oauth_reconnect_required}
        end
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :oauth_reconnect_required}
    end
  end

  defp credentials(
         %ResolvedMCPConnection{connection: %{auth_method: method}} = saved,
         _,
         _,
         _,
         _,
         _
       )
       when method in ~w(none bearer headers basic), do: {:ok, saved}

  defp credentials(_, _, _, _, _, _), do: {:error, :mcp_connection_unavailable}

  defp refresh_state(nil, _now), do: :ok

  defp refresh_state(%{"deadline" => deadline}, now) when is_integer(deadline) do
    if deadline > DateTime.to_unix(now),
      do: {:error, :oauth_refresh_in_progress},
      else: {:error, :oauth_reconnect_required}
  end

  defp refresh_state(_, _), do: {:error, :oauth_reconnect_required}
  defp expiry(nil), do: {:ok, nil}

  defp expiry(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> {:error, :oauth_reconnect_required}
    end
  end

  defp expiry(_), do: {:error, :oauth_reconnect_required}
end
