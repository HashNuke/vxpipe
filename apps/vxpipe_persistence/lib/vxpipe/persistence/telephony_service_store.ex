defmodule Vxpipe.Persistence.TelephonyServiceStore do
  @moduledoc "PostgreSQL tenant service bindings with credential ownership enforced at storage."
  @behaviour Vxpipe.Calls.TelephonyServiceRepository

  import Ecto.Query

  alias Vxpipe.Calls.TelephonyService, as: Service
  alias Vxpipe.Calls.{ResolvedTelephonyService, TelephonyServices}
  alias Vxpipe.Persistence.{ProviderCredentialScope, ProviderCredentialStore, TelnyxRouting}

  alias Vxpipe.Persistence.Schema.{
    ProviderCredential,
    TelephonyRoute,
    TelephonyService,
    TelnyxSettings
  }

  @query_options [log: false, telemetry_event: nil]

  @impl true
  def with_configuration(context, scope, operation) do
    with_repository(context, fn repo ->
      repo.transaction(
        fn ->
          TelnyxRouting.lock(repo, :write)

          with {:ok, _owner} <- ProviderCredentialScope.owner(repo, scope, "FOR UPDATE"),
               {:ok, result} <- operation.() do
            result
          else
            {:error, reason} -> repo.rollback(reason)
          end
        end,
        @query_options
      )
    end)
  end

  @impl true
  def platform_application(context) do
    with_repository(context, fn repo ->
      {:ok, repo.get!(TelnyxSettings, 1, @query_options).application_id}
    end)
  end

  @impl true
  def configure_platform_application(context, application_id) do
    with_repository(context, fn repo ->
      transaction(repo, fn ->
        settings = TelnyxRouting.lock(repo, :write)

        with :ok <- TelnyxRouting.validate_default(repo, application_id),
             {:ok, _} <-
               repo.update(TelnyxSettings.changeset(settings, application_id), @query_options) do
          :ok
        else
          {:error, %Ecto.Changeset{}} -> {:error, :invalid_telephony_service}
          error -> error
        end
      end)
    end)
  end

  @impl true
  def register(context, %Service{} = service) do
    with :ok <- Service.validate(service) do
      with_repository(context, fn repo ->
        repo.transaction(fn ->
          TelnyxRouting.lock(repo, :write)

          with :ok <- TelnyxRouting.validate_application(repo, service),
               {:ok, {tenant_id, _private_snapshot}} <- lock_credential(context, service),
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
  def update_application(context, tenant_key, id, changes) do
    with_repository(context, fn repo ->
      repo.transaction(fn ->
        TelnyxRouting.lock(repo, :write)

        query =
          from(s in TelephonyService,
            join: t in assoc(s, :tenant),
            where:
              t.key == ^tenant_key and s.public_id == ^id and s.provider == "telnyx" and
                s.credential_name == "telnyx",
            select: s,
            lock: "FOR UPDATE"
          )

        case repo.one(query, @query_options) do
          nil -> repo.rollback(:telephony_service_not_found)
          stored -> update_locked_application(context, stored, tenant_key, changes)
        end
      end)
    end)
  end

  defp update_locked_application(context, stored, tenant_key, changes) do
    repo = Keyword.fetch!(context, :repo)
    service = metadata(stored, tenant_key)

    updated = %{
      service
      | provider_connection_id:
          Map.get(changes, "provider_connection_id", service.provider_connection_id),
        outbound_number: Map.get(changes, "outbound_number", service.outbound_number)
    }

    with :ok <- Service.validate(updated),
         :ok <- TelnyxRouting.validate_application(repo, updated),
         {:ok, {_tenant_id, _credential}} <- lock_credential(context, updated),
         {:ok, saved} <-
           repo.update(
             TelephonyService.changeset(
               stored,
               Map.take(updated, [:provider_connection_id, :outbound_number])
             ),
             @query_options
           ) do
      metadata(saved, tenant_key)
    else
      {:error, %Ecto.Changeset{} = changeset} -> repo.rollback(insertion_error(changeset))
      {:error, reason} -> repo.rollback(reason)
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

  @impl true
  def fetch_telnyx_application(context, application_id) do
    with_repository(context, fn repo ->
      query =
        from(s in TelephonyService,
          join: t in assoc(s, :tenant),
          where:
            s.provider == "telnyx" and s.credential_name == "telnyx" and
              s.provider_connection_id == ^application_id,
          select: {s, t.key}
        )

      fetch_metadata(repo, query)
    end)
  end

  @impl true
  def fetch_telnyx_route(context, scope, application_id, number) do
    with_repository(context, fn repo ->
      query =
        from(service in TelephonyService,
          join: tenant in assoc(service, :tenant),
          join: settings in TelnyxSettings,
          on: settings.id == 1,
          join: route in TelephonyRoute,
          on: route.tenant_id == service.tenant_id and route.service == service.name,
          join: revision in assoc(route, :call_spec_revision),
          join: spec in assoc(revision, :call_spec),
          where:
            service.provider == "telnyx" and service.credential_name == "telnyx" and
              fragment("coalesce(?, ?)", service.provider_connection_id, settings.application_id) ==
                ^application_id and
              route.number == ^number and not is_nil(route.published_at) and
              spec.published_revision_id == revision.id,
          select: {service, tenant.key},
          limit: 2
        )

      query =
        case scope do
          :platform -> query
          {:tenant, key} -> from([_service, tenant] in query, where: tenant.key == ^key)
        end

      case repo.all(query, @query_options) do
        [{service, tenant_key}] -> {:ok, metadata(service, tenant_key)}
        _unknown_or_ambiguous -> {:error, :telephony_service_not_found}
      end
    end)
  end

  @impl true
  def resolve(context, tenant_key, name) do
    with_repository(context, fn repo ->
      transaction(repo, fn -> resolve_locked(context, tenant_key, name) end)
    end)
  end

  @impl true
  def with_active(context, tenant_key, requirements, operation) do
    with_repository(context, fn repo ->
      transaction(repo, fn ->
        mode =
          if Enum.any?(requirements, &Map.get(&1, :publishing?, false)), do: :publish, else: :read

        TelnyxRouting.lock(repo, mode)
        _ = lock_requirements(context, tenant_key, requirements)
        operation.()
      end)
    end)
  end

  defp lock_requirements(context, tenant_key, requirements) do
    repo = Keyword.fetch!(context, :repo)

    requirements
    |> Enum.sort_by(&{&1.name, &1.path})
    |> Enum.reduce(%{}, fn requirement, snapshots ->
      snapshot =
        Map.get_lazy(snapshots, requirement.name, fn ->
          required_snapshot(context, tenant_key, requirement)
        end)

      unless Vxpipe.Calls.ProviderCredential.allowed_owner?(
               snapshot.credential.credential,
               Map.get(requirement, :allowed_owner)
             ) do
        repo.rollback({:provider_service_forbidden, requirement.path})
      end

      case TelephonyServices.check_requirement(snapshot.service, requirement) do
        :ok -> :ok
        {:error, reason} -> repo.rollback({reason, requirement.path})
      end

      Map.put(snapshots, requirement.name, snapshot)
    end)
  end

  defp required_snapshot(context, tenant_key, requirement) do
    case resolve_locked(context, tenant_key, requirement.name) do
      {:ok, snapshot} ->
        snapshot

      {:error, _reason} ->
        repo = Keyword.fetch!(context, :repo)
        repo.rollback({:provider_credential_unavailable, requirement.path})
    end
  end

  defp resolve_locked(context, tenant_key, name) do
    repo = Keyword.fetch!(context, :repo)
    TelnyxRouting.lock(repo, :read)

    query =
      from(s in TelephonyService,
        join: t in assoc(s, :tenant),
        where: t.key == ^tenant_key and s.name == ^name,
        select: {s, t.key},
        lock: "FOR SHARE"
      )

    with {:ok, service} <- fetch_metadata(repo, query),
         :ok <- Service.validate(service),
         {:ok, service} <- resolve_application(repo, service),
         {:ok, {_tenant_id, credential}} <- lock_credential(context, service) do
      resolved = resolved_service(service, credential)
      {:ok, %ResolvedTelephonyService{service: resolved, credential: credential}}
    end
  end

  defp resolve_application(
         repo,
         %{provider: "telnyx", credential_name: "telnyx", provider_connection_id: nil} = service
       ) do
    settings = repo.get!(TelnyxSettings, 1, @query_options)

    if Service.application_id?(settings.application_id),
      do:
        {:ok,
         %{
           service
           | provider_connection_id: settings.application_id,
             application_owner: :platform
         }},
      else: {:error, :provider_credential_unavailable}
  end

  defp resolve_application(_repo, %{provider: "telnyx", credential_name: "telnyx"} = service),
    do: {:ok, %{service | application_owner: {:tenant, service.tenant_key}}}

  defp resolve_application(_repo, service), do: {:ok, service}

  defp transaction(repo, operation) do
    case repo.transaction(fn ->
           case operation.() do
             {:error, reason} -> repo.rollback(reason)
             result -> result
           end
         end) do
      {:ok, result} -> result
      {:error, _reason} = error -> error
    end
  end

  defp resolved_service(%{credential_name: nil} = service, _credential), do: service

  defp resolved_service(service, credential) do
    %{
      service
      | credential_id: credential.credential.id,
        credential_owner: Vxpipe.Calls.ProviderCredential.owner(credential.credential),
        public_key: Map.fetch!(credential.payload, "public_key")
    }
  end

  defp lock_credential(context, %{credential_name: "telnyx"} = service) do
    repo = Keyword.fetch!(context, :repo)

    with {:ok, owner} <- ProviderCredentialScope.owner(repo, service.tenant_key, "FOR SHARE"),
         {:ok, credential} <-
           ProviderCredentialStore.resolve(
             context,
             service.tenant_key,
             service.provider,
             service.credential_name
           ),
         true <-
           Vxpipe.Providers.Telnyx.Credential.public_key?(
             Map.get(credential.payload, "public_key")
           ),
         :ok <- application_credentials(service, credential) do
      {:ok, {owner.id, credential}}
    else
      {:error, :telnyx_application_required} = error -> error
      _unavailable -> {:error, :provider_credential_unavailable}
    end
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
         {:ok, private_snapshot} <-
           ProviderCredentialStore.resolve(
             context,
             service.tenant_key,
             service.provider,
             credential.name
           ),
         true <- private_snapshot.credential.id == service.credential_id,
         true <- Service.credential_matches?(service, private_snapshot.payload) do
      {:ok, {credential.tenant_id, private_snapshot}}
    else
      _unavailable -> {:error, :provider_credential_unavailable}
    end
  end

  defp application_credentials(service, credential) do
    inherited? = is_nil(service.provider_connection_id) or service.application_owner == :platform

    platform_credentials? =
      Vxpipe.Calls.ProviderCredential.owner(credential.credential) == :platform

    if inherited? and not platform_credentials?,
      do: {:error, :telnyx_application_required},
      else: :ok
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
    |> Map.drop([
      :id,
      :tenant_key,
      :credential_owner,
      :application_owner,
      :inserted_at,
      :updated_at
    ])
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
      credential_name: stored.credential_name,
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
