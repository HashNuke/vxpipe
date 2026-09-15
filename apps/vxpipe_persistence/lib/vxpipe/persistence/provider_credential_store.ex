defmodule Vxpipe.Persistence.ProviderCredentialStore do
  @moduledoc "Encrypted PostgreSQL adapter for tenant provider credentials. Queries never log bound data."
  @behaviour Vxpipe.Calls.ProviderCredentialRepository

  import Ecto.Query

  alias Vxpipe.Calls.{ProviderAuth, ResolvedProviderCredential}
  alias Vxpipe.Calls.ProviderCredential, as: Credential
  alias Vxpipe.Persistence.CredentialCipher
  alias Vxpipe.Persistence.Schema.{ProviderCredential, Tenant}

  @impl true
  def provision(context, %Credential{} = credential, payload) do
    repo = Keyword.fetch!(context, :repo)

    with :ok <- ProviderAuth.binding(credential.tenant_key, credential.provider, credential.name),
         :ok <- ProviderAuth.validate(credential.provider, credential.auth_kind, payload),
         {:ok, key_id, encrypted} <-
           CredentialCipher.encrypt(Keyword.get(context, :keyring), credential, payload),
         {:ok, tenant} <- tenant(repo, credential.tenant_key) do
      attributes = %{
        public_id: credential.id,
        tenant_id: tenant.id,
        provider: credential.provider,
        name: credential.name,
        auth_kind: credential.auth_kind,
        version: credential.version,
        payload_schema_version: credential.payload_schema_version,
        status: "active",
        encrypted_payload: encrypted,
        encryption_key_id: key_id
      }

      case repo.insert(ProviderCredential.changeset(%ProviderCredential{}, attributes),
             log: false,
             telemetry_event: nil
           ) do
        {:ok, stored} -> {:ok, metadata(stored, tenant.key)}
        {:error, changeset} -> {:error, insertion_error(changeset)}
      end
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @impl true
  def list(context, tenant_key) do
    repo = Keyword.fetch!(context, :repo)

    with {:ok, tenant} <- tenant(repo, tenant_key) do
      credentials =
        repo.all(
          from(c in ProviderCredential,
            where: c.tenant_id == ^tenant.id,
            order_by: [c.provider, c.name]
          ),
          log: false,
          telemetry_event: nil
        )

      {:ok, Enum.map(credentials, &metadata(&1, tenant.key))}
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @impl true
  def resolve(context, tenant_key, provider, name) do
    repo = Keyword.fetch!(context, :repo)

    query =
      from(c in ProviderCredential,
        join: t in assoc(c, :tenant),
        where: t.key == ^tenant_key and c.provider == ^provider and c.name == ^name
      )

    case repo.one(query, log: false, telemetry_event: nil) do
      nil -> {:error, :provider_credential_not_found}
      %{status: "revoked"} -> {:error, :provider_credential_revoked}
      %{status: "active"} = stored -> resolve_payload(context, stored, tenant_key)
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  # Match the dependency boundary, not exception text or all RuntimeErrors.
  # Programmer errors elsewhere retain their original exception and stacktrace.
  defp repository_error(%DBConnection.ConnectionError{}, _trace),
    do: {:error, :provider_credentials_unavailable}

  defp repository_error(%Postgrex.Error{}, _trace),
    do: {:error, :provider_credentials_unavailable}

  defp repository_error(%RuntimeError{}, [{Ecto.Repo.Registry, :lookup, _, _} | _]),
    do: {:error, :provider_credentials_unavailable}

  defp repository_error(%ArgumentError{}, [
         {:ets, :lookup_element, [Ecto.Repo.Registry | _], _} | _
       ]),
       do: {:error, :provider_credentials_unavailable}

  defp repository_error(error, trace), do: reraise(error, trace)

  defp resolve_payload(context, stored, tenant_key) do
    credential = metadata(stored, tenant_key)

    with true <- credential.payload_schema_version == 1,
         {:ok, payload} <-
           CredentialCipher.decrypt(
             Keyword.get(context, :keyring),
             credential,
             stored.encryption_key_id,
             stored.encrypted_payload
           ),
         :ok <- ProviderAuth.validate(credential.provider, credential.auth_kind, payload) do
      {:ok, %ResolvedProviderCredential{credential: credential, payload: payload}}
    else
      {:error, :credential_key_unavailable} = error -> error
      _invalid -> {:error, :provider_credential_unreadable}
    end
  end

  defp tenant(repo, key) do
    case repo.get_by(Tenant, [key: key], log: false, telemetry_event: nil) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, tenant}
    end
  end

  defp insertion_error(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
         Keyword.get(metadata, :constraint) == :unique
       end), do: :provider_credential_conflict, else: :provider_credential_write_failed
  end

  defp metadata(stored, tenant_key) do
    %Credential{
      id: stored.public_id,
      tenant_key: tenant_key,
      provider: stored.provider,
      name: stored.name,
      auth_kind: stored.auth_kind,
      version: stored.version,
      payload_schema_version: stored.payload_schema_version,
      encryption_key_id: stored.encryption_key_id,
      status: status(stored.status),
      inserted_at: stored.inserted_at,
      updated_at: stored.updated_at
    }
  end

  defp status("active"), do: :active
  defp status("revoked"), do: :revoked
end
