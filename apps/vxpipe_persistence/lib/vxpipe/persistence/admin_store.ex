defmodule Vxpipe.Persistence.AdminStore do
  @moduledoc "Ecto adapter for installation-operator read workflows."

  @behaviour Vxpipe.Calls.AdminRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallDirectorySummary, CallSpecFilter, CallSpecSummary}
  alias Vxpipe.Calls.ProviderCredential, as: DomainProviderCredential
  alias Vxpipe.Calls.TelephonyService, as: DomainTelephonyService
  alias Vxpipe.Calls.Tenant, as: DomainTenant

  alias Vxpipe.Persistence.Schema.{
    Call,
    CallSpec,
    CallDetailsPublication,
    CallSpecRevision,
    ProviderCredential,
    TelephonyService,
    Tenant
  }

  @call_spec_filter_limit 100
  @service_inventory_limit 100

  @impl true
  def list_tenants(repo, limit, offset) do
    page_query =
      from(tenant in Tenant,
        order_by: [desc: tenant.inserted_at, desc: tenant.key],
        limit: ^limit,
        offset: ^offset,
        select: %{
          key: tenant.key,
          name: tenant.name,
          inserted_at: tenant.inserted_at
        }
      )

    total_query = from(tenant in Tenant, select: %{value: count(tenant.id)})

    query =
      from(total in subquery(total_query),
        left_join: tenant in subquery(page_query),
        on: true,
        order_by: [desc: tenant.inserted_at, desc: tenant.key],
        select: {tenant.key, tenant.name, tenant.inserted_at, total.value}
      )

    repository_result(fn ->
      query
      |> repo.all()
      |> tenant_page()
    end)
  end

  @impl true
  def list_call_specs(repo, tenant_key, limit, offset) do
    latest_numbers =
      from(revision in CallSpecRevision,
        group_by: revision.call_spec_id,
        select: %{
          call_spec_id: revision.call_spec_id,
          revision: max(revision.revision)
        }
      )

    call_counts =
      from(call in Call,
        join: revision in CallSpecRevision,
        on: revision.id == call.call_spec_revision_id,
        group_by: revision.call_spec_id,
        select: %{call_spec_id: revision.call_spec_id, value: count(call.id)}
      )

    call_spec_page =
      from(call_spec in CallSpec,
        join: tenant in Tenant,
        on: tenant.id == call_spec.tenant_id,
        join: latest_number in subquery(latest_numbers),
        on: latest_number.call_spec_id == call_spec.id,
        join: latest in CallSpecRevision,
        on:
          latest.call_spec_id == call_spec.id and
            latest.revision == latest_number.revision,
        left_join: published in CallSpecRevision,
        on: published.id == call_spec.published_revision_id,
        left_join: calls in subquery(call_counts),
        on: calls.call_spec_id == call_spec.id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: latest.inserted_at, desc: call_spec.public_id],
        limit: ^limit,
        offset: ^offset,
        select: %{
          tenant_id: call_spec.tenant_id,
          id: call_spec.public_id,
          name: fragment("?->>'name'", latest.source),
          latest_revision: latest.revision,
          published_revision: published.revision,
          call_count: coalesce(calls.value, 0),
          updated_at: latest.inserted_at
        }
      )

    totals =
      from(call_spec in CallSpec,
        group_by: call_spec.tenant_id,
        select: %{tenant_id: call_spec.tenant_id, value: count(call_spec.id)}
      )

    query =
      from(tenant in Tenant,
        left_join: total in subquery(totals),
        on: total.tenant_id == tenant.id,
        left_join: call_spec in subquery(call_spec_page),
        on: call_spec.tenant_id == tenant.id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: call_spec.updated_at, desc: call_spec.id],
        select: {
          tenant.key,
          tenant.name,
          tenant.inserted_at,
          call_spec.id,
          call_spec.name,
          call_spec.latest_revision,
          call_spec.published_revision,
          call_spec.call_count,
          call_spec.updated_at,
          coalesce(total.value, 0)
        }
      )

    repository_result(fn ->
      query
      |> repo.all()
      |> call_spec_page()
    end)
  end

  @impl true
  def list_calls(repo, tenant_key, call_spec_id, limit, offset) do
    repository_result(fn ->
      with {:ok, {tenant, tenant_id}} <- fetch_tenant(repo, tenant_key),
           {:ok, {call_specs, call_specs_truncated}} <-
             filter_call_specs(repo, tenant_id, call_spec_id),
           {:ok, {calls, total}} <-
             call_page(repo, tenant_id, call_spec_id, limit, offset) do
        {:ok, {tenant, call_specs, call_specs_truncated, calls, total}}
      end
    end)
  end

  @impl true
  def fetch_call_context(repo, tenant_key, call_id) do
    repository_result(fn ->
      with {:ok, {tenant, tenant_id}} <- fetch_tenant(repo, tenant_key) do
        query =
          from(call in Call,
            join: revision in CallSpecRevision,
            on: revision.id == call.call_spec_revision_id,
            join: call_spec in CallSpec,
            on: call_spec.id == revision.call_spec_id,
            left_join: publication in CallDetailsPublication,
            on: publication.id == call.latest_details_publication_id,
            where: call.tenant_id == ^tenant_id and call.public_id == ^call_id,
            select: {
              call.public_id,
              call_spec.public_id,
              fragment("?->>'name'", revision.source),
              revision.revision,
              call.state,
              call.created_at,
              call.started_at,
              call.ended_at,
              call.terminal_reason,
              publication.completeness
            }
          )

        case repo.one(query) do
          nil -> {:error, :call_not_found}
          row -> {:ok, {tenant, call_summary(row)}}
        end
      end
    end)
  end

  @impl true
  def list_services(repo, tenant_key) do
    repository_result(fn ->
      with {:ok, {tenant, tenant_id}} <- fetch_tenant(repo, tenant_key) do
        credentials =
          ProviderCredential
          |> where([credential], credential.tenant_id == ^tenant_id)
          |> order_by([credential], asc: credential.provider, asc: credential.name)
          |> limit(^(@service_inventory_limit + 1))
          |> select(
            [credential],
            struct(credential, [
              :public_id,
              :provider,
              :name,
              :auth_kind,
              :version,
              :payload_schema_version,
              :status,
              :secret_hints,
              :last_validated_at,
              :encryption_key_id,
              :inserted_at,
              :updated_at
            ])
          )
          |> repo.all()
          |> Enum.map(&credential_metadata(&1, tenant.key))

        {visible_credentials, remaining_credentials} =
          Enum.split(credentials, @service_inventory_limit)

        visible_credential_ids = Enum.map(visible_credentials, & &1.id)

        services =
          TelephonyService
          |> where(
            [service],
            service.tenant_id == ^tenant_id and
              service.credential_id in ^visible_credential_ids
          )
          |> order_by([service], asc: service.provider, asc: service.name)
          |> limit(^(@service_inventory_limit + 1))
          |> select(
            [service],
            struct(service, [
              :public_id,
              :name,
              :ingress_key,
              :provider,
              :provider_connection_id,
              :credential_id,
              :public_key,
              :outbound_number,
              :answering_machine_detection,
              :media_token_ttl_ms,
              :webhook_tolerance_seconds,
              :inserted_at,
              :updated_at
            ])
          )
          |> repo.all()
          |> Enum.map(&telephony_metadata(&1, tenant.key))

        {visible_services, remaining_services} = Enum.split(services, @service_inventory_limit)

        {:ok,
         {tenant, visible_credentials, visible_services,
          remaining_credentials != [] or remaining_services != []}}
      end
    end)
  end

  defp tenant_page([{nil, nil, nil, total}]), do: {:ok, {[], total}}

  defp tenant_page(rows) do
    {tenants, totals} =
      Enum.map_reduce(rows, [], fn {key, name, inserted_at, total}, totals ->
        {%DomainTenant{key: key, name: name, inserted_at: inserted_at}, [total | totals]}
      end)

    case Enum.uniq(totals) do
      [total] -> {:ok, {tenants, total}}
      _inconsistent -> {:error, :repository_unavailable}
    end
  end

  defp call_spec_page([]), do: {:error, :tenant_not_found}

  defp call_spec_page([
         {key, tenant_name, tenant_inserted_at, nil, nil, nil, nil, nil, nil, total}
       ]) do
    tenant = %DomainTenant{key: key, name: tenant_name, inserted_at: tenant_inserted_at}
    {:ok, {tenant, [], total}}
  end

  defp call_spec_page(rows) do
    [{key, tenant_name, tenant_inserted_at, _, _, _, _, _, _, total} | _rest] = rows
    tenant = %DomainTenant{key: key, name: tenant_name, inserted_at: tenant_inserted_at}

    call_specs =
      Enum.map(rows, fn {_key, _tenant_name, _tenant_inserted_at, id, name, latest_revision,
                         published_revision, call_count, updated_at, ^total} ->
        %CallSpecSummary{
          id: id,
          name: name,
          latest_revision: latest_revision,
          published_revision: published_revision,
          call_count: call_count,
          updated_at: updated_at
        }
      end)

    {:ok, {tenant, call_specs, total}}
  end

  defp fetch_tenant(repo, tenant_key) do
    query =
      from(tenant in Tenant,
        where: tenant.key == ^tenant_key,
        select: {tenant.id, tenant.key, tenant.name, tenant.inserted_at}
      )

    case repo.one(query) do
      nil ->
        {:error, :tenant_not_found}

      {id, key, name, inserted_at} ->
        {:ok, {%DomainTenant{key: key, name: name, inserted_at: inserted_at}, id}}
    end
  end

  defp filter_call_specs(repo, tenant_id, selected_id) do
    latest_numbers = latest_revision_numbers()

    rows =
      CallSpec
      |> join(:inner, [call_spec], latest_number in subquery(latest_numbers),
        on: latest_number.call_spec_id == call_spec.id
      )
      |> join(:inner, [call_spec, latest_number], latest in CallSpecRevision,
        on:
          latest.call_spec_id == call_spec.id and
            latest.revision == latest_number.revision
      )
      |> where([call_spec], call_spec.tenant_id == ^tenant_id)
      |> order_by(
        [call_spec, _latest_number, latest],
        asc: fragment("lower(?->>'name')", latest.source),
        asc: call_spec.public_id
      )
      |> limit(^(@call_spec_filter_limit + 1))
      |> select(
        [call_spec, _latest_number, latest],
        {call_spec.public_id, fragment("?->>'name'", latest.source)}
      )
      |> repo.all()

    {visible_rows, remaining_rows} = Enum.split(rows, @call_spec_filter_limit)

    call_specs =
      Enum.map(visible_rows, fn {id, name} ->
        %CallSpecFilter{id: id, name: name}
      end)

    include_selected_call_spec(
      repo,
      tenant_id,
      call_specs,
      remaining_rows != [],
      selected_id
    )
  end

  defp include_selected_call_spec(_repo, _tenant_id, call_specs, truncated, nil),
    do: {:ok, {call_specs, truncated}}

  defp include_selected_call_spec(repo, tenant_id, call_specs, truncated, selected_id) do
    case Enum.find(call_specs, &(&1.id == selected_id)) do
      %CallSpecFilter{} ->
        {:ok, {call_specs, truncated}}

      nil ->
        query =
          from(call_spec in CallSpec,
            join: latest_number in subquery(latest_revision_numbers()),
            on: latest_number.call_spec_id == call_spec.id,
            join: latest in CallSpecRevision,
            on:
              latest.call_spec_id == call_spec.id and
                latest.revision == latest_number.revision,
            where: call_spec.tenant_id == ^tenant_id and call_spec.public_id == ^selected_id,
            select: {call_spec.public_id, fragment("?->>'name'", latest.source)}
          )

        case repo.one(query) do
          nil ->
            {:error, :call_spec_not_found}

          {id, name} ->
            {:ok, {call_specs ++ [%CallSpecFilter{id: id, name: name}], truncated}}
        end
    end
  end

  defp call_page(repo, tenant_id, call_spec_id, limit, offset) do
    base_query =
      from(call in Call,
        join: revision in CallSpecRevision,
        on: revision.id == call.call_spec_revision_id,
        join: call_spec in CallSpec,
        on: call_spec.id == revision.call_spec_id,
        left_join: publication in CallDetailsPublication,
        on: publication.id == call.latest_details_publication_id,
        where: call.tenant_id == ^tenant_id
      )
      |> call_spec_filter(call_spec_id)

    page_query =
      from([call, revision, call_spec, publication] in base_query,
        order_by: [desc: call.created_at, desc: call.public_id],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: call.public_id,
          call_spec_id: call_spec.public_id,
          call_spec_name: fragment("?->>'name'", revision.source),
          call_spec_revision: revision.revision,
          state: call.state,
          created_at: call.created_at,
          started_at: call.started_at,
          ended_at: call.ended_at,
          terminal_reason: call.terminal_reason,
          archive_state: publication.completeness
        }
      )

    total_query =
      from([call, _revision, _call_spec, _publication] in base_query,
        select: %{value: count(call.id)}
      )

    query =
      from(total in subquery(total_query),
        left_join: call in subquery(page_query),
        on: true,
        order_by: [desc: call.created_at, desc: call.id],
        select: {
          call.id,
          call.call_spec_id,
          call.call_spec_name,
          call.call_spec_revision,
          call.state,
          call.created_at,
          call.started_at,
          call.ended_at,
          call.terminal_reason,
          call.archive_state,
          total.value
        }
      )

    query
    |> repo.all()
    |> call_rows()
  end

  defp call_spec_filter(query, nil), do: query

  defp call_spec_filter(query, call_spec_id) do
    from([_call, _revision, call_spec, _publication] in query,
      where: call_spec.public_id == ^call_spec_id
    )
  end

  defp call_rows([{nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, total}]),
    do: {:ok, {[], total}}

  defp call_rows(rows) do
    {calls, totals} =
      Enum.map_reduce(rows, [], fn
        {id, call_spec_id, call_spec_name, call_spec_revision, state, created_at, started_at,
         ended_at, terminal_reason, archive_state, total},
        totals ->
          call =
            call_summary({
              id,
              call_spec_id,
              call_spec_name,
              call_spec_revision,
              state,
              created_at,
              started_at,
              ended_at,
              terminal_reason,
              archive_state
            })

          {call, [total | totals]}
      end)

    case Enum.uniq(totals) do
      [total] -> {:ok, {calls, total}}
      _inconsistent -> {:error, :repository_unavailable}
    end
  end

  defp call_summary(
         {id, call_spec_id, call_spec_name, call_spec_revision, state, created_at, started_at,
          ended_at, terminal_reason, archive_state}
       ) do
    %CallDirectorySummary{
      id: id,
      call_spec_id: call_spec_id,
      call_spec_name: call_spec_name,
      call_spec_revision: call_spec_revision,
      state: state,
      created_at: created_at,
      started_at: started_at,
      ended_at: ended_at,
      terminal_reason: terminal_reason,
      archive_state: archive_state || :unconfirmed
    }
  end

  defp latest_revision_numbers do
    from(revision in CallSpecRevision,
      group_by: revision.call_spec_id,
      select: %{
        call_spec_id: revision.call_spec_id,
        revision: max(revision.revision)
      }
    )
  end

  defp credential_metadata(stored, tenant_key) do
    %DomainProviderCredential{
      id: stored.public_id,
      tenant_key: tenant_key,
      provider: stored.provider,
      name: stored.name,
      auth_kind: stored.auth_kind,
      version: stored.version,
      payload_schema_version: stored.payload_schema_version,
      status: credential_status(stored.status),
      secret_hints: stored.secret_hints || %{},
      last_validated_at: stored.last_validated_at,
      encryption_key_id: stored.encryption_key_id,
      inserted_at: stored.inserted_at,
      updated_at: stored.updated_at
    }
  end

  defp telephony_metadata(stored, tenant_key) do
    %DomainTelephonyService{
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

  defp credential_status("active"), do: :active
  defp credential_status("revoked"), do: :revoked

  defp detection("disabled"), do: :disabled
  defp detection("detect"), do: :detect

  defp repository_result(operation) do
    operation.()
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error, RuntimeError] ->
      {:error, :repository_unavailable}
  catch
    :exit, _reason -> {:error, :repository_unavailable}
  end
end
