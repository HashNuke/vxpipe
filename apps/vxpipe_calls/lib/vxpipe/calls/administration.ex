defmodule Vxpipe.Calls.Administration do
  @moduledoc "Trusted tenant and API-key administration workflows."

  alias Vxpipe.Calls.{IssuedApiKey, Principal, PublicId, Repositories, Tenant}

  @scopes [:admin, :calls]
  @maximum_attempts 4

  @spec bootstrap_tenant(String.t(), [atom()], keyword()) ::
          {:ok, Tenant.t(), IssuedApiKey.t()} | {:error, term()}
  def bootstrap_tenant(name, scopes, options \\ []) do
    with {:ok, name} <- validate_name(name),
         {:ok, scopes} <- validate_scopes(scopes),
         {:ok, repository} <- Repositories.fetch(options, :credential_repository) do
      attempt_bootstrap(repository, name, scopes, options, @maximum_attempts)
    end
  end

  @spec issue_api_key(String.t(), String.t(), [atom()], keyword()) ::
          {:ok, IssuedApiKey.t()} | {:error, term()}
  def issue_api_key(tenant_key, name, scopes, options \\ []) do
    with :ok <- validate_tenant_key(tenant_key),
         {:ok, name} <- validate_name(name),
         {:ok, scopes} <- validate_scopes(scopes),
         {:ok, repository} <- Repositories.fetch(options, :credential_repository) do
      attempt_key_issue(repository, tenant_key, name, scopes, options, @maximum_attempts)
    end
  end

  @spec authenticate(String.t(), String.t(), atom(), keyword()) ::
          {:ok, Principal.t()} | {:error, term()}
  def authenticate(tenant_key, secret, required_scope, options \\ []) do
    with :ok <- validate_tenant_key(tenant_key),
         :ok <- validate_required_scope(required_scope),
         true <- is_binary(secret),
         {:ok, repository} <- Repositories.fetch(options, :credential_repository),
         digest = :crypto.hash(:sha256, secret),
         {:ok, api_key} <- Repositories.call(repository, :fetch_api_key, [tenant_key, digest]) do
      authenticate_record(api_key, tenant_key, required_scope)
    else
      false -> {:error, :invalid_api_key}
      {:error, :not_found} -> {:error, :invalid_api_key}
      {:error, _reason} = error -> error
    end
  end

  @spec revoke_api_key(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def revoke_api_key(tenant_key, api_key_id, options \\ []) do
    with :ok <- validate_tenant_key(tenant_key),
         :ok <- validate_uuid(api_key_id),
         {:ok, repository} <- Repositories.fetch(options, :credential_repository) do
      Repositories.call(repository, :revoke_api_key, [
        tenant_key,
        api_key_id,
        now(options)
      ])
    end
  end

  defp attempt_bootstrap(_repository, _name, _scopes, _options, 0),
    do: {:error, :identifier_generation_exhausted}

  defp attempt_bootstrap(repository, name, scopes, options, attempts_left) do
    inserted_at = now(options)
    tenant = %Tenant{key: tenant_key(options), name: name, inserted_at: inserted_at}
    {issued, stored} = key_pair(tenant.key, "bootstrap", scopes, inserted_at, options)

    case Repositories.call(repository, :bootstrap_tenant, [tenant, stored]) do
      {:ok, {_tenant, _api_key}} -> {:ok, tenant, issued}
      {:error, reason} when reason in [:tenant_key_conflict, :api_key_id_conflict] ->
        attempt_bootstrap(repository, name, scopes, options, attempts_left - 1)

      {:error, _reason} = error -> error
    end
  end

  defp attempt_key_issue(_repository, _tenant_key, _name, _scopes, _options, 0),
    do: {:error, :identifier_generation_exhausted}

  defp attempt_key_issue(repository, tenant_key, name, scopes, options, attempts_left) do
    inserted_at = now(options)
    {issued, stored} = key_pair(tenant_key, name, scopes, inserted_at, options)

    case Repositories.call(repository, :insert_api_key, [tenant_key, stored]) do
      {:ok, _api_key} -> {:ok, issued}
      {:error, :api_key_id_conflict} ->
        attempt_key_issue(repository, tenant_key, name, scopes, options, attempts_left - 1)

      {:error, _reason} = error -> error
    end
  end

  defp key_pair(tenant_key, name, scopes, inserted_at, options) do
    id = uuid(options)
    secret = api_key(options)

    issued = %IssuedApiKey{
      id: id,
      tenant_key: tenant_key,
      name: name,
      scopes: scopes,
      secret: secret,
      inserted_at: inserted_at
    }

    stored = %{
      id: id,
      tenant_key: tenant_key,
      name: name,
      scopes: scopes,
      digest: :crypto.hash(:sha256, secret),
      revoked_at: nil,
      inserted_at: inserted_at
    }

    {issued, stored}
  end

  defp validate_name(value) when is_binary(value) do
    value = String.trim(value)

    if value != "" and byte_size(value) <= 256,
      do: {:ok, value},
      else: {:error, :invalid_name}
  end

  defp validate_name(_value), do: {:error, :invalid_name}

  defp validate_scopes(scopes) when is_list(scopes) and scopes != [] do
    if Enum.all?(scopes, &(&1 in @scopes)) do
      {:ok, MapSet.new(scopes)}
    else
      {:error, :invalid_scopes}
    end
  end

  defp validate_scopes(_scopes), do: {:error, :invalid_scopes}

  defp validate_required_scope(scope) when scope in @scopes, do: :ok
  defp validate_required_scope(_scope), do: {:error, :invalid_scope}

  defp authenticate_record(%{revoked_at: %DateTime{}}, _tenant_key, _required_scope),
    do: {:error, :invalid_api_key}

  defp authenticate_record(api_key, tenant_key, required_scope) do
    if MapSet.member?(api_key.scopes, required_scope) do
      {:ok,
       %Principal{
         tenant_key: tenant_key,
         api_key_id: api_key.id,
         scopes: api_key.scopes
       }}
    else
      {:error, :insufficient_scope}
    end
  end

  defp validate_tenant_key(value) when is_binary(value) and byte_size(value) == 16, do: :ok
  defp validate_tenant_key(_value), do: {:error, :invalid_tenant_key}

  defp validate_uuid(value) when is_binary(value) do
    if Regex.match?(
         ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
         value
       ),
      do: :ok,
      else: {:error, :invalid_api_key_id}
  end

  defp validate_uuid(_value), do: {:error, :invalid_api_key_id}

  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)
  defp tenant_key(options), do: generate(options, :tenant_key_generator, &PublicId.tenant_key/0)
  defp api_key(options), do: generate(options, :api_key_generator, &PublicId.api_key/0)
  defp uuid(options), do: generate(options, :uuid_generator, &PublicId.uuid/0)

  defp generate(options, key, fallback) do
    options
    |> Keyword.get(key, fallback)
    |> then(& &1.())
  end
end
