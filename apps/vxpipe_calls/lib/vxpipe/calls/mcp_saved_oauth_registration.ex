defmodule Vxpipe.Calls.MCPSavedOAuthRegistration do
  @moduledoc "Loads only the registration identity of a current tenant OAuth connection."
  alias Vxpipe.Calls.Repositories

  @fields ~w(registration_method client_id client_secret client_secret_expires_at auth_method issuer resource redirect_uri scopes)

  def fetch(repository, tenant, %{status: "connected", auth_method: "oauth"} = connection) do
    with {:ok, resolved} <- Repositories.call(repository, :resolve, [tenant, connection.id]),
         :ok <- same_connection(resolved.connection, connection, tenant) do
      {:ok, Map.take(resolved.secrets, @fields)}
    else
      {:error, reason} when reason in [:credential_key_unavailable, :mcp_secret_unreadable] ->
        {:ok, %{}}

      error ->
        error
    end
  end

  def fetch(_repository, _tenant, _connection), do: {:ok, %{}}

  defp same_connection(current, expected, tenant) do
    cond do
      current.id != expected.id or current.tenant_key != tenant ->
        {:error, :invalid_oauth_reconnect}

      current.generation != expected.generation ->
        {:error, :stale_mcp_connection}

      current.endpoint != expected.endpoint or current.status != "connected" or
          current.auth_method != "oauth" ->
        {:error, :invalid_oauth_reconnect}

      true ->
        :ok
    end
  end
end
