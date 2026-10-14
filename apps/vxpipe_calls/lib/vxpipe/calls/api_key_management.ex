defmodule Vxpipe.Calls.ApiKeyManagement do
  @moduledoc "User-authorized Vxpipe API-key lifecycle. Secrets are returned only on creation."
  alias Vxpipe.Calls.{ApiKeyAccess, PublicId, Repositories}

  def list(principal, params, options \\ []) do
    with :ok <- visible(principal),
         {:ok, query} <- query(params),
         {:ok, repository} <- repository(options) do
      Repositories.call(repository, :list, [
        ApiKeyAccess.scope(principal, :read),
        ApiKeyAccess.platform_read?(principal),
        query
      ])
    end
  end

  def tenants(principal, kind, params, options \\ []) when kind in ["calls", "full"] do
    with :ok <- visible(principal),
         {:ok, query} <- query(params),
         {:ok, repository} <- repository(options) do
      mode = if kind == "calls", do: :calls, else: :full
      Repositories.call(repository, :tenants, [ApiKeyAccess.scope(principal, mode), query])
    end
  end

  def create(principal, name, kind, tenant, options \\ []) do
    with :ok <- ApiKeyAccess.authorize_create(principal, kind, tenant),
         {:ok, name} <- name(name),
         {:ok, repository} <- repository(options) do
      prefix = if kind == "platform", do: "vxpk_", else: "vxak_"
      secret = prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      record = %{
        id: PublicId.uuid(),
        name: name,
        tenant_key: tenant,
        kind: kind,
        scopes: scopes(kind),
        digest: :crypto.hash(:sha256, secret),
        last_four: String.slice(secret, -4, 4)
      }

      with {:ok, key} <- Repositories.call(repository, :insert, [record]),
           do: {:ok, %{key: key, secret: secret}}
    end
  end

  def revoke(principal, id, options \\ []) do
    with {:ok, repository} <- repository(options),
         {:ok, key} <- Repositories.call(repository, :fetch, [id]),
         tenant = if(key.tenant, do: key.tenant.key),
         :ok <- ApiKeyAccess.authorize_write(principal, tenant) do
      Repositories.call(repository, :revoke, [id, DateTime.utc_now()])
    end
  end

  def authenticate_platform(secret, options \\ []) do
    with true <- is_binary(secret) and Regex.match?(~r/\Avxpk_[A-Za-z0-9_-]{43}\z/, secret),
         {:ok, repository} <- repository(options),
         {:ok, id} <-
           Repositories.call(repository, :authenticate_platform, [:crypto.hash(:sha256, secret)]) do
      {:ok, %Vxpipe.Calls.InstallationOperator{grant: :installation_operator, api_key_id: id}}
    else
      false -> {:error, :invalid_api_key}
      {:error, _} = error -> error
    end
  end

  defp visible(principal),
    do: if(ApiKeyAccess.visible?(principal), do: :ok, else: {:error, :forbidden})

  defp repository(options), do: Repositories.fetch(options, :access_key_repository)
  defp scopes("calls"), do: ["calls"]
  defp scopes("full"), do: ["admin", "calls"]
  defp scopes("platform"), do: ["platform"]

  defp name(value) when is_binary(value) do
    value = String.trim(value)
    if value != "" and byte_size(value) <= 256, do: {:ok, value}, else: {:error, :invalid_name}
  end

  defp name(_), do: {:error, :invalid_name}

  defp query(params) do
    q = Map.get(params, "q", "")

    with true <-
           is_binary(q) and String.valid?(q) and String.length(q) <= 120 and
             not String.contains?(q, <<0>>),
         {page, ""} when page > 0 and page <= 1_000_000 <-
           Integer.parse(to_string(Map.get(params, "page", "1"))) do
      {:ok, %{query: String.trim(q), limit: 25, offset: (page - 1) * 25, page: page}}
    else
      _ -> {:error, :invalid_query}
    end
  rescue
    Protocol.UndefinedError -> {:error, :invalid_query}
    ArgumentError -> {:error, :invalid_query}
  end
end
