defmodule Vxpipe.Persistence.AdminStore do
  @moduledoc "Ecto adapter for installation-operator read workflows."

  @behaviour Vxpipe.Calls.AdminRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallDirectorySummary, CallFilterDefinition, DefinitionSummary}
  alias Vxpipe.Calls.Tenant, as: DomainTenant

  alias Vxpipe.Persistence.Schema.{
    Call,
    CallDefinition,
    CallDetailsPublication,
    DefinitionRevision,
    Tenant
  }

  @definition_filter_limit 100

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

  @impl true
  def list_calls(repo, tenant_key, definition_id, limit, offset) do
    repository_result(fn ->
      with {:ok, {tenant, tenant_id}} <- fetch_tenant(repo, tenant_key),
           {:ok, {definitions, definitions_truncated}} <-
             filter_definitions(repo, tenant_id, definition_id),
           {:ok, {calls, total}} <-
             call_page(repo, tenant_id, definition_id, limit, offset) do
        {:ok, {tenant, definitions, definitions_truncated, calls, total}}
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

  defp filter_definitions(repo, tenant_id, selected_id) do
    latest_numbers = latest_revision_numbers()

    rows =
      CallDefinition
      |> join(:inner, [definition], latest_number in subquery(latest_numbers),
        on: latest_number.definition_id == definition.id
      )
      |> join(:inner, [definition, latest_number], latest in DefinitionRevision,
        on:
          latest.call_definition_id == definition.id and
            latest.revision == latest_number.revision
      )
      |> where([definition], definition.tenant_id == ^tenant_id)
      |> order_by(
        [definition, _latest_number, latest],
        asc: fragment("lower(?->>'name')", latest.source),
        asc: definition.public_id
      )
      |> limit(^(@definition_filter_limit + 1))
      |> select(
        [definition, _latest_number, latest],
        {definition.public_id, fragment("?->>'name'", latest.source)}
      )
      |> repo.all()

    {visible_rows, remaining_rows} = Enum.split(rows, @definition_filter_limit)

    definitions =
      Enum.map(visible_rows, fn {id, name} ->
        %CallFilterDefinition{id: id, name: name}
      end)

    include_selected_definition(
      repo,
      tenant_id,
      definitions,
      remaining_rows != [],
      selected_id
    )
  end

  defp include_selected_definition(_repo, _tenant_id, definitions, truncated, nil),
    do: {:ok, {definitions, truncated}}

  defp include_selected_definition(repo, tenant_id, definitions, truncated, selected_id) do
    case Enum.find(definitions, &(&1.id == selected_id)) do
      %CallFilterDefinition{} ->
        {:ok, {definitions, truncated}}

      nil ->
        query =
          from(definition in CallDefinition,
            join: latest_number in subquery(latest_revision_numbers()),
            on: latest_number.definition_id == definition.id,
            join: latest in DefinitionRevision,
            on:
              latest.call_definition_id == definition.id and
                latest.revision == latest_number.revision,
            where: definition.tenant_id == ^tenant_id and definition.public_id == ^selected_id,
            select: {definition.public_id, fragment("?->>'name'", latest.source)}
          )

        case repo.one(query) do
          nil ->
            {:error, :definition_not_found}

          {id, name} ->
            {:ok, {definitions ++ [%CallFilterDefinition{id: id, name: name}], truncated}}
        end
    end
  end

  defp call_page(repo, tenant_id, definition_id, limit, offset) do
    base_query =
      from(call in Call,
        join: revision in DefinitionRevision,
        on: revision.id == call.definition_revision_id,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        left_join: publication in CallDetailsPublication,
        on: publication.id == call.latest_details_publication_id,
        where: call.tenant_id == ^tenant_id
      )
      |> call_definition_filter(definition_id)

    page_query =
      from([call, revision, definition, publication] in base_query,
        order_by: [desc: call.created_at, desc: call.public_id],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: call.public_id,
          definition_id: definition.public_id,
          definition_name: fragment("?->>'name'", revision.source),
          definition_revision: revision.revision,
          state: call.state,
          created_at: call.created_at,
          started_at: call.started_at,
          ended_at: call.ended_at,
          terminal_reason: call.terminal_reason,
          archive_state: publication.completeness
        }
      )

    total_query =
      from([call, _revision, _definition, _publication] in base_query,
        select: %{value: count(call.id)}
      )

    query =
      from(total in subquery(total_query),
        left_join: call in subquery(page_query),
        on: true,
        order_by: [desc: call.created_at, desc: call.id],
        select: {
          call.id,
          call.definition_id,
          call.definition_name,
          call.definition_revision,
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

  defp call_definition_filter(query, nil), do: query

  defp call_definition_filter(query, definition_id) do
    from([_call, _revision, definition, _publication] in query,
      where: definition.public_id == ^definition_id
    )
  end

  defp call_rows([{nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, total}]),
    do: {:ok, {[], total}}

  defp call_rows(rows) do
    {calls, totals} =
      Enum.map_reduce(rows, [], fn
        {id, definition_id, definition_name, definition_revision, state, created_at, started_at,
         ended_at, terminal_reason, archive_state, total},
        totals ->
          call = %CallDirectorySummary{
            id: id,
            definition_id: definition_id,
            definition_name: definition_name,
            definition_revision: definition_revision,
            state: state,
            created_at: created_at,
            started_at: started_at,
            ended_at: ended_at,
            terminal_reason: terminal_reason,
            archive_state: archive_state || :unconfirmed
          }

          {call, [total | totals]}
      end)

    case Enum.uniq(totals) do
      [total] -> {:ok, {calls, total}}
      _inconsistent -> {:error, :repository_unavailable}
    end
  end

  defp latest_revision_numbers do
    from(revision in DefinitionRevision,
      group_by: revision.call_definition_id,
      select: %{
        definition_id: revision.call_definition_id,
        revision: max(revision.revision)
      }
    )
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
