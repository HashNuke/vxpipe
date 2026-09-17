defmodule Vxpipe.Persistence.AdminStore do
  @moduledoc "Ecto adapter for installation-operator read workflows."

  @behaviour Vxpipe.Calls.AdminRepository

  import Ecto.Query

  alias Vxpipe.Calls.DefinitionSummary
  alias Vxpipe.Calls.Tenant, as: DomainTenant
  alias Vxpipe.Persistence.Schema.{Call, CallDefinition, DefinitionRevision, Tenant}

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
  def list_definitions(repo, tenant_key, limit, offset) do
    latest_numbers =
      from(revision in DefinitionRevision,
        group_by: revision.call_definition_id,
        select: %{
          definition_id: revision.call_definition_id,
          revision: max(revision.revision)
        }
      )

    call_counts =
      from(call in Call,
        join: revision in DefinitionRevision,
        on: revision.id == call.definition_revision_id,
        group_by: revision.call_definition_id,
        select: %{definition_id: revision.call_definition_id, value: count(call.id)}
      )

    definition_page =
      from(definition in CallDefinition,
        join: tenant in Tenant,
        on: tenant.id == definition.tenant_id,
        join: latest_number in subquery(latest_numbers),
        on: latest_number.definition_id == definition.id,
        join: latest in DefinitionRevision,
        on:
          latest.call_definition_id == definition.id and
            latest.revision == latest_number.revision,
        left_join: published in DefinitionRevision,
        on: published.id == definition.published_revision_id,
        left_join: calls in subquery(call_counts),
        on: calls.definition_id == definition.id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: latest.inserted_at, desc: definition.public_id],
        limit: ^limit,
        offset: ^offset,
        select: %{
          tenant_id: definition.tenant_id,
          id: definition.public_id,
          name: fragment("?->>'name'", latest.source),
          latest_revision: latest.revision,
          published_revision: published.revision,
          call_count: coalesce(calls.value, 0),
          updated_at: latest.inserted_at
        }
      )

    totals =
      from(definition in CallDefinition,
        group_by: definition.tenant_id,
        select: %{tenant_id: definition.tenant_id, value: count(definition.id)}
      )

    query =
      from(tenant in Tenant,
        left_join: total in subquery(totals),
        on: total.tenant_id == tenant.id,
        left_join: definition in subquery(definition_page),
        on: definition.tenant_id == tenant.id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: definition.updated_at, desc: definition.id],
        select: {
          tenant.key,
          tenant.name,
          tenant.inserted_at,
          definition.id,
          definition.name,
          definition.latest_revision,
          definition.published_revision,
          definition.call_count,
          definition.updated_at,
          coalesce(total.value, 0)
        }
      )

    repository_result(fn ->
      query
      |> repo.all()
      |> definition_page()
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

  defp definition_page([]), do: {:error, :tenant_not_found}

  defp definition_page([
         {key, tenant_name, tenant_inserted_at, nil, nil, nil, nil, nil, nil, total}
       ]) do
    tenant = %DomainTenant{key: key, name: tenant_name, inserted_at: tenant_inserted_at}
    {:ok, {tenant, [], total}}
  end

  defp definition_page(rows) do
    [{key, tenant_name, tenant_inserted_at, _, _, _, _, _, _, total} | _rest] = rows
    tenant = %DomainTenant{key: key, name: tenant_name, inserted_at: tenant_inserted_at}

    definitions =
      Enum.map(rows, fn {_key, _tenant_name, _tenant_inserted_at, id, name, latest_revision,
                         published_revision, call_count, updated_at, ^total} ->
        %DefinitionSummary{
          id: id,
          name: name,
          latest_revision: latest_revision,
          published_revision: published_revision,
          call_count: call_count,
          updated_at: updated_at
        }
      end)

    {:ok, {tenant, definitions, total}}
  end

  defp repository_result(operation) do
    operation.()
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error, RuntimeError] ->
      {:error, :repository_unavailable}
  catch
    :exit, _reason -> {:error, :repository_unavailable}
  end
end
