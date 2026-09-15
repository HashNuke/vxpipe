defmodule Vxpipe.Persistence.TelephonyServiceStore do
  @moduledoc "PostgreSQL tenant service bindings with credential ownership enforced at storage."
  @behaviour Vxpipe.Calls.TelephonyServiceRepository

  import Ecto.Query

  alias Vxpipe.Calls.TelephonyService, as: Service
  alias Vxpipe.Persistence.ProviderCredentialStore
  alias Vxpipe.Persistence.Schema.{ProviderCredential, TelephonyService}

  @query_options [log: false, telemetry_event: nil]

  @impl true
  def register(context, %Service{} = service) do
    with :ok <- Service.validate(service) do
      with_repository(context, fn repo ->
        repo.transaction(fn ->
          with {:ok, tenant_id} <- lock_credential(context, service),
               {:ok, stored} <-
                 repo.insert(
                   TelephonyService.changeset(
                     %TelephonyService{},
                     attributes(service, tenant_id)
                   ),
                   @query_options
                 ) do
            metadata(stored, service.tenant_key)
          else
            {:error, %Ecto.Changeset{} = changeset} -> repo.rollback(insertion_error(changeset))
            {:error, reason} -> repo.rollback(reason)
          end
        end)
      end)
    end
  end

  @impl true
  def fetch(context, tenant_key, name) do
    with_repository(context, fn repo ->
      query =
        from(s in TelephonyService,
          join: t in assoc(s, :tenant),
          where: t.key == ^tenant_key and s.name == ^name,
          select: {s, t.key}
        )

      fetch_metadata(repo, query)
    end)
  end

  @impl true
  def fetch_by_ingress(context, ingress_key) do
    with_repository(context, fn repo ->
      query =
        from(s in TelephonyService,
          join: t in assoc(s, :tenant),
          where: s.ingress_key == ^ingress_key,
          select: {s, t.key}
        )

      fetch_metadata(repo, query)
    end)
  end

  defp lock_credential(context, service) do
    repo = Keyword.fetch!(context, :repo)

    query =
      from(c in ProviderCredential,
        join: t in assoc(c, :tenant),
        where:
          c.public_id == ^service.credential_id and t.key == ^service.tenant_key and
            c.provider == ^service.provider,
        lock: "FOR SHARE"
      )

    with %{status: "active"} = credential <- repo.one(query, @query_options),
         {:ok, _private_snapshot} <-
           ProviderCredentialStore.resolve(
             context,
             service.tenant_key,
             service.provider,
             credential.name
           ) do
      {:ok, credential.tenant_id}
    else
      _unavailable -> {:error, :provider_credential_unavailable}
    end
  end

  defp fetch_metadata(repo, query) do
    case repo.one(query, @query_options) do
      nil -> {:error, :telephony_service_not_found}
      {stored, tenant_key} -> {:ok, metadata(stored, tenant_key)}
    end
  end

  defp attributes(service, tenant_id) do
    service
    |> Map.from_struct()
    |> Map.drop([:id, :tenant_key, :inserted_at, :updated_at])
    |> Map.merge(%{public_id: service.id, tenant_id: tenant_id})
    |> Map.update!(:answering_machine_detection, &Atom.to_string/1)
  end

  defp metadata(stored, tenant_key) do
    %Service{
      id: stored.public_id,
      tenant_key: tenant_key,
      name: stored.name,
      ingress_key: stored.ingress_key,
      provider: stored.provider,
      provider_connection_id: stored.provider_connection_id,
      credential_id: stored.credential_id,
      public_key: stored.public_key,
      outbound_number: stored.outbound_number,
      answering_machine_detection: detection(stored.answering_machine_detection),
      media_token_ttl_ms: stored.media_token_ttl_ms,
      webhook_tolerance_seconds: stored.webhook_tolerance_seconds,
      inserted_at: stored.inserted_at,
      updated_at: stored.updated_at
    }
  end

  defp detection("disabled"), do: :disabled
  defp detection("detect"), do: :detect

  defp insertion_error(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
         Keyword.get(metadata, :constraint) == :unique
       end), do: :telephony_service_conflict, else: :telephony_service_write_failed
  end

  defp with_repository(context, operation) do
    operation.(Keyword.fetch!(context, :repo))
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :telephony_services_unavailable}

    error ->
      case __STACKTRACE__ do
        [{Ecto.Repo.Registry, :lookup, _, _} | _] ->
          {:error, :telephony_services_unavailable}

        [{:ets, :lookup_element, [Ecto.Repo.Registry | _], _} | _] ->
          {:error, :telephony_services_unavailable}

        _programming_error ->
          reraise(error, __STACKTRACE__)
      end
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} ->
      {:error, :telephony_services_unavailable}
  end
end
