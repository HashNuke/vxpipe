defmodule Vxpipe.Persistence.ProviderCredentialStore do
  @moduledoc "Encrypted PostgreSQL adapter for scoped provider credentials. Queries never log bound data."
  @behaviour Vxpipe.Calls.ProviderCredentialRepository

  import Ecto.Query

  alias Vxpipe.Calls.{ProviderAuth, ResolvedProviderCredential}
  alias Vxpipe.Calls.ProviderCredential, as: Credential
  alias Vxpipe.Persistence.{CredentialCipher, CredentialKeyring, ProviderCredentialScope}
  alias Vxpipe.Persistence.Schema.ProviderCredential

  @private_query_options [log: false, telemetry_event: nil]

  @impl true
  def provision(context, %Credential{} = credential, payload) do
    repo = Keyword.fetch!(context, :repo)

    with :ok <-
           ProviderAuth.binding(
             Credential.owner(credential),
             credential.provider,
             credential.name
           ),
         :ok <- ProviderAuth.validate(credential.provider, credential.auth_kind, payload),
         {:ok, key_id, encrypted} <-
           CredentialCipher.encrypt(Keyword.get(context, :keyring), credential, payload) do
      repo.transaction(
        fn ->
          with {:ok, owner} <-
                 ProviderCredentialScope.owner(repo, Credential.owner(credential), "FOR UPDATE"),
               attributes = %{
                 public_id: credential.id,
                 scope: owner.scope,
                 tenant_id: owner.id,
                 provider: credential.provider,
                 name: credential.name,
                 auth_kind: credential.auth_kind,
                 version: credential.version,
                 payload_schema_version: credential.payload_schema_version,
                 status: "active",
                 secret_hints: credential.secret_hints,
                 last_validated_at: credential.last_validated_at,
                 encrypted_payload: encrypted,
                 encryption_key_id: key_id
               },
               {:ok, stored} <-
                 repo.insert(
                   ProviderCredential.changeset(%ProviderCredential{}, attributes),
                   @private_query_options
                 ) do
            metadata(stored, owner.key)
          else
            {:error, %Ecto.Changeset{} = changeset} -> repo.rollback(insertion_error(changeset))
            {:error, reason} -> repo.rollback(reason)
          end
        end,
        @private_query_options
      )
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @impl true
  def replace(
        context,
        tenant_key,
        credential_id,
        provider,
        auth_kind,
        payload,
        secret_hints,
        last_validated_at
      ) do
    repo = Keyword.fetch!(context, :repo)

    case repo.transaction(
           fn ->
             owner =
               case ProviderCredentialScope.owner(repo, tenant_key, "FOR UPDATE") do
                 {:ok, owner} -> owner
                 {:error, _reason} -> repo.rollback(:provider_credential_not_found)
               end

             query = ProviderCredentialScope.owned(ProviderCredential, owner)

             query =
               from(c in query,
                 where: c.public_id == ^credential_id and c.provider == ^provider,
                 lock: "FOR UPDATE"
               )

             stored =
               repo.one(query, @private_query_options) ||
                 repo.rollback(:provider_credential_not_found)

             next = %{
               metadata(stored, owner.key)
               | auth_kind: auth_kind,
                 version: stored.version + 1,
                 status: :active,
                 secret_hints: secret_hints,
                 last_validated_at: last_validated_at
             }

             with :ok <- ProviderAuth.validate(provider, auth_kind, payload),
                  {:ok, key_id, encrypted} <-
                    CredentialCipher.encrypt(Keyword.get(context, :keyring), next, payload),
                  {:ok, updated} <-
                    repo.update(
                      Ecto.Changeset.change(stored,
                        auth_kind: auth_kind,
                        version: next.version,
                        status: "active",
                        secret_hints: secret_hints,
                        last_validated_at: last_validated_at,
                        encrypted_payload: encrypted,
                        encryption_key_id: key_id
                      ),
                      @private_query_options
                    ) do
               metadata(updated, owner.key)
             else
               {:error, %Ecto.Changeset{}} -> repo.rollback(:provider_credential_write_failed)
               {:error, reason} -> repo.rollback(reason)
             end
           end,
           @private_query_options
         ) do
      {:ok, credential} -> {:ok, credential}
      {:error, reason} -> {:error, reason}
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

    with {:ok, owner} <- ProviderCredentialScope.owner(repo, tenant_key) do
      query = ProviderCredentialScope.owned(ProviderCredential, owner)

      credentials =
        repo.all(
          from(c in query, order_by: [c.provider, c.name]),
          log: false,
          telemetry_event: nil
        )

      {:ok, Enum.map(credentials, &metadata(&1, owner.key))}
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @impl true
  def list_bindings(context, owner) do
    Vxpipe.Persistence.ProviderServiceDirectory.list(context, owner)
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @doc false
  def setup_metadata(context, stored, tenant_key) do
    case {stored.status, resolve_payload(context, stored, tenant_key)} do
      {"active", {:ok, resolved}} ->
        fields =
          Enum.filter(
            ~w(api_key public_key account_sid auth_token),
            &Map.has_key?(resolved.payload, &1)
          )

        %{status: :connected, saved_fields: fields}

      {"revoked", _result} ->
        %{status: :invalid, saved_fields: []}

      _unreadable ->
        %{status: :unavailable, saved_fields: []}
    end
  end

  @impl true
  def resolve(context, tenant_key, provider, name) do
    repo = Keyword.fetch!(context, :repo)

    case repo.transaction(
           fn -> resolve_selected(context, tenant_key, provider, name) end,
           @private_query_options
         ) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @impl true
  def delete(context, scope, credential_id) do
    repo = Keyword.fetch!(context, :repo)

    case repo.transaction(
           fn ->
             unless match?({:ok, _id}, Ecto.UUID.cast(credential_id)),
               do: repo.rollback(:invalid_provider_credential_id)

             with {:ok, owner} <- ProviderCredentialScope.owner(repo, scope, "FOR UPDATE"),
                  query = ProviderCredentialScope.owned(ProviderCredential, owner),
                  %ProviderCredential{} = stored <-
                    repo.one(
                      from(c in query, where: c.public_id == ^credential_id, lock: "FOR UPDATE"),
                      @private_query_options
                    ),
                  changeset =
                    Ecto.Changeset.change(stored)
                    |> Ecto.Changeset.foreign_key_constraint(:public_id,
                      name: :telephony_services_credential_owner_fkey
                    ),
                  {:ok, _deleted} <- repo.delete(changeset, @private_query_options) do
               :ok
             else
               nil -> repo.rollback(:provider_credential_not_found)
               {:error, %Ecto.Changeset{}} -> repo.rollback(:provider_credential_in_use)
               {:error, reason} -> repo.rollback(reason)
             end
           end,
           @private_query_options
         ) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  @impl true
  def with_active(context, tenant_key, requirements, operation) do
    repo = Keyword.fetch!(context, :repo)

    case repo.transaction(fn ->
           requirements
           |> Enum.sort_by(&{&1.provider, &1.name})
           |> Enum.each(fn requirement ->
             case lock_active(context, tenant_key, requirement) do
               :ok ->
                 :ok

               {:error, :provider_service_forbidden} ->
                 repo.rollback({:provider_service_forbidden, requirement.path})

               {:error, _reason} ->
                 repo.rollback({:provider_credential_unavailable, requirement.path})
             end
           end)

           case operation.() do
             {:error, reason} -> repo.rollback(reason)
             result -> result
           end
         end) do
      {:ok, result} -> result
      {:error, _reason} = error -> error
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  defp lock_active(context, tenant_key, requirement) do
    case resolve_selected(context, tenant_key, requirement.provider, requirement.name) do
      {:ok, snapshot} ->
        cond do
          not Credential.allowed_owner?(snapshot.credential, Map.get(requirement, :allowed_owner)) ->
            {:error, :provider_service_forbidden}

          not Map.has_key?(requirement, :identity) or
              requirement.identity == Credential.binding_identity(snapshot.credential) ->
            :ok

          true ->
            {:error, :provider_credential_unavailable}
        end

      {:error, _reason} ->
        {:error, :provider_credential_unavailable}
    end
  end

  @doc """
  Re-encrypt one bounded batch with the platform's current key, preserving tenant credentials.

  Busy rows are skipped and included in remaining counts. Successful batches commit atomically;
  rerun after incomplete progress. All credential readers and writers must have the new keyring
  before the operator retires an old key.
  """
  @spec reencrypt(keyword(), pos_integer()) :: {:ok, map()} | {:error, atom()}
  def reencrypt(context, batch_size \\ 100)

  def reencrypt(context, batch_size)
      when is_list(context) and is_integer(batch_size) and batch_size in 1..500 do
    repo = Keyword.fetch!(context, :repo)

    with {:ok, current_key_id, _key} <- CredentialKeyring.current(Keyword.get(context, :keyring)) do
      repo.transaction(
        fn ->
          rows =
            repo.all(
              from(c in ProviderCredential,
                left_join: t in assoc(c, :tenant),
                where: c.encryption_key_id != ^current_key_id,
                order_by: c.id,
                limit: ^batch_size,
                select: {c, t.key},
                lock: fragment("FOR UPDATE OF ? SKIP LOCKED", c)
              ),
              @private_query_options
            )

          Enum.each(rows, &reencrypt_row(context, &1))

          %{
            processed: length(rows),
            current_key_id: current_key_id,
            remaining_by_key: remaining_encryption_keys(repo, current_key_id)
          }
        end,
        @private_query_options
      )
    end
  rescue
    error -> repository_error(error, __STACKTRACE__)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :provider_credentials_unavailable}
  end

  def reencrypt(_context, _batch_size), do: {:error, :invalid_reencryption_batch_size}

  defp reencrypt_row(context, {stored, tenant_key}) do
    repo = Keyword.fetch!(context, :repo)

    with {:ok, resolved} <- resolve_payload(context, stored, tenant_key),
         {:ok, key_id, encrypted} <-
           CredentialCipher.encrypt(
             Keyword.get(context, :keyring),
             resolved.credential,
             resolved.payload
           ),
         {:ok, _updated} <-
           repo.update(
             Ecto.Changeset.change(stored,
               encrypted_payload: encrypted,
               encryption_key_id: key_id
             ),
             @private_query_options
           ) do
      :ok
    else
      {:error, %Ecto.Changeset{}} -> repo.rollback(:provider_credential_write_failed)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp remaining_encryption_keys(repo, current_key_id) do
    from(c in ProviderCredential,
      where: c.encryption_key_id != ^current_key_id,
      group_by: c.encryption_key_id,
      select: {c.encryption_key_id, count(c.id)}
    )
    |> repo.all(@private_query_options)
    |> Map.new()
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

  defp resolve_selected(context, tenant_key, provider, name) do
    repo = Keyword.fetch!(context, :repo)

    with {:ok, owner} <- ProviderCredentialScope.selected(repo, tenant_key, provider, name) do
      query = ProviderCredentialScope.owned(ProviderCredential, owner)

      query =
        from(c in query,
          where: c.provider == ^provider and c.name == ^name,
          lock: "FOR SHARE"
        )

      case repo.one(query, @private_query_options) do
        nil -> {:error, :provider_credential_not_found}
        %{status: "revoked"} -> {:error, :provider_credential_revoked}
        %{status: "active"} = stored -> resolve_payload(context, stored, owner.key)
      end
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
      owner: if(stored.scope == "platform", do: :platform, else: {:tenant, tenant_key}),
      provider: stored.provider,
      name: stored.name,
      auth_kind: stored.auth_kind,
      version: stored.version,
      payload_schema_version: stored.payload_schema_version,
      encryption_key_id: stored.encryption_key_id,
      status: status(stored.status),
      secret_hints: stored.secret_hints || %{},
      last_validated_at: stored.last_validated_at,
      inserted_at: stored.inserted_at,
      updated_at: stored.updated_at
    }
  end

  defp status("active"), do: :active
  defp status("revoked"), do: :revoked
end
