defmodule Vxpipe.Persistence.DefinitionStore do
  @moduledoc "Ecto adapter for immutable definition revisions and deployment routes."

  @behaviour Vxpipe.Calls.DefinitionRepository

  import Ecto.Query

  alias Ecto.Multi
  alias Vxpipe.Calls.{DefinitionRevision, ParticipantRoute, TelephonyRoute}
  alias Vxpipe.Persistence.Schema.{CallDefinition, Tenant}
  alias Vxpipe.Persistence.Schema.DefinitionRevision, as: StoredRevision
  alias Vxpipe.Persistence.Schema.ParticipantRoute, as: StoredRoute
  alias Vxpipe.Persistence.Schema.TelephonyRoute, as: StoredTelephonyRoute

  @impl true
  def next_revision(repo, tenant_key, definition_id) do
    query =
      from(revision in StoredRevision,
        join: definition in assoc(revision, :call_definition),
        join: tenant in assoc(definition, :tenant),
        where: tenant.key == ^tenant_key and definition.public_id == ^definition_id,
        select: max(revision.revision)
      )

    {:ok, (repo.one(query) || 0) + 1}
  end

  @impl true
  def insert_revision(repo, tenant_key, revision, routes) do
    multi =
      Multi.new()
      |> Multi.run(:tenant, fn repo, _changes -> fetch_tenant(repo, tenant_key) end)
      |> Multi.run(:definition, fn repo, %{tenant: tenant} ->
        fetch_or_insert_definition(repo, tenant, revision.definition_id)
      end)
      |> Multi.insert(:revision, fn %{definition: definition} ->
        StoredRevision.changeset(%StoredRevision{}, %{
          call_definition_id: definition.id,
          revision: revision.revision,
          schema_version: revision.schema_version,
          source: revision.source,
          source_digest: revision.source_digest,
          compiled_metadata: revision.compiled_metadata,
          validation_errors: revision.validation_errors
        })
      end)
      |> Multi.run(:routes, fn repo, %{tenant: tenant, revision: stored_revision} ->
        insert_routes(repo, tenant, stored_revision, routes)
      end)
      |> Multi.run(:telephony_routes, fn repo, %{tenant: tenant, revision: stored_revision} ->
        insert_telephony_routes(repo, tenant, stored_revision, revision.telephony_routes)
      end)

    case repo.transaction(multi) do
      {:ok,
       %{
         definition: definition,
         revision: stored_revision,
         routes: stored_routes,
         telephony_routes: stored_telephony_routes
       }} ->
        {:ok,
         to_revision(
           definition,
           stored_revision,
           stored_routes,
           stored_telephony_routes,
           tenant_key
         )}

      {:error, :revision, changeset, _changes} ->
        if Keyword.has_key?(changeset.errors, :revision),
          do: {:error, :revision_conflict},
          else: {:error, :revision_insert_failed}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_revision(repo, tenant_key, definition_id, revision_number) do
    query =
      from(revision in StoredRevision,
        join: definition in assoc(revision, :call_definition),
        join: tenant in assoc(definition, :tenant),
        where:
          tenant.key == ^tenant_key and definition.public_id == ^definition_id and
            revision.revision == ^revision_number,
        preload: [:participant_routes, :telephony_routes],
        select: {definition, revision}
      )

    case repo.one(query) do
      nil ->
        {:error, :not_found}

      {definition, revision} ->
        {:ok,
         to_revision(
           definition,
           revision,
           revision.participant_routes,
           revision.telephony_routes,
           tenant_key
         )}
    end
  end

  @impl true
  def publish_revision(repo, tenant_key, definition_id, revision_number, published_at) do
    multi =
      Multi.new()
      |> Multi.run(:selection, fn repo, _changes ->
        fetch_stored_revision(repo, tenant_key, definition_id, revision_number)
      end)
      |> Multi.run(:disable_old_routes, fn repo, %{selection: {definition, _revision}} ->
        route_query = routes_for_definition(definition.id)
        {count, _rows} = repo.update_all(route_query, set: [published_at: nil])
        {:ok, count}
      end)
      |> Multi.run(:disable_old_telephony_routes, fn repo,
                                                     %{selection: {definition, _revision}} ->
        route_query = telephony_routes_for_definition(definition.id)
        {count, _rows} = repo.update_all(route_query, set: [published_at: nil])
        {:ok, count}
      end)
      |> Multi.run(:enable_routes, fn repo, %{selection: {_definition, revision}} ->
        route_query =
          from(route in StoredRoute, where: route.definition_revision_id == ^revision.id)

        {count, _rows} = repo.update_all(route_query, set: [published_at: published_at])
        {:ok, count}
      end)
      |> Multi.run(:enable_telephony_routes, fn repo, %{selection: {_definition, revision}} ->
        route_query =
          from(route in StoredTelephonyRoute,
            where: route.definition_revision_id == ^revision.id
          )

        {count, _rows} = repo.update_all(route_query, set: [published_at: published_at])
        {:ok, count}
      end)
      |> Multi.update(:definition, fn %{selection: {definition, revision}} ->
        CallDefinition.changeset(definition, %{
          published_revision_id: revision.id,
          published_at: published_at
        })
      end)

    case repo.transaction(multi) do
      {:ok, %{definition: definition, selection: {_definition, revision}}} ->
        routes =
          repo.all(
            from(route in StoredRoute, where: route.definition_revision_id == ^revision.id)
          )

        telephony_routes =
          repo.all(
            from(route in StoredTelephonyRoute,
              where: route.definition_revision_id == ^revision.id
            )
          )

        {:ok, to_revision(definition, revision, routes, telephony_routes, tenant_key)}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  @impl true
  def resolve_route(repo, tenant_key, route_key) do
    query =
      from(route in StoredRoute,
        join: tenant in assoc(route, :tenant),
        join: revision in assoc(route, :definition_revision),
        join: definition in assoc(revision, :call_definition),
        where:
          tenant.key == ^tenant_key and route.public_id == ^route_key and
            not is_nil(route.published_at) and definition.published_revision_id == revision.id,
        select: {route, tenant.key, definition.public_id, revision.revision}
      )

    case repo.one(query) do
      nil ->
        {:error, :route_unavailable}

      {route, key, definition_id, definition_revision} ->
        {:ok, to_route(route, key, definition_id, definition_revision)}
    end
  end

  @impl true
  def resolve_telephony_route(repo, scope, service, number) do
    query =
      from(route in StoredTelephonyRoute,
        join: tenant in assoc(route, :tenant),
        join: revision in assoc(route, :definition_revision),
        join: definition in assoc(revision, :call_definition),
        where:
          route.service == ^service and route.number == ^number and
            not is_nil(route.published_at) and definition.published_revision_id == revision.id,
        select: {route, tenant.key, definition.public_id, revision.revision},
        limit: 2
      )

    matches = repo.all(scope_telephony_routes(query, scope))

    case matches do
      [{route, tenant_key, definition_id, definition_revision}] ->
        {:ok, to_telephony_route(route, tenant_key, definition_id, definition_revision)}

      _none_or_ambiguous ->
        {:error, :route_unavailable}
    end
  end

  defp fetch_tenant(repo, tenant_key) do
    case repo.get_by(Tenant, key: tenant_key) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, tenant}
    end
  end

  defp fetch_or_insert_definition(repo, tenant, definition_id) do
    changeset =
      CallDefinition.changeset(%CallDefinition{}, %{
        tenant_id: tenant.id,
        public_id: definition_id
      })

    {:ok, _definition} =
      repo.insert(changeset,
        on_conflict: :nothing,
        conflict_target: [:tenant_id, :public_id]
      )

    {:ok, repo.get_by!(CallDefinition, tenant_id: tenant.id, public_id: definition_id)}
  end

  defp insert_routes(repo, tenant, revision, routes) do
    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, stored_routes} ->
      changeset =
        StoredRoute.changeset(%StoredRoute{}, %{
          public_id: route.key,
          participant_ref: route.participant_ref,
          published_at: nil,
          tenant_id: tenant.id,
          definition_revision_id: revision.id
        })

      case repo.insert(changeset) do
        {:ok, stored} ->
          {:cont, {:ok, [stored | stored_routes]}}

        {:error, changeset} ->
          reason =
            if Keyword.has_key?(changeset.errors, :public_id),
              do: :participant_route_key_conflict,
              else: :participant_route_insert_failed

          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, stored_routes} -> {:ok, Enum.reverse(stored_routes)}
      {:error, _reason} = error -> error
    end
  end

  defp insert_telephony_routes(repo, tenant, revision, routes) do
    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, stored_routes} ->
      changeset =
        StoredTelephonyRoute.changeset(%StoredTelephonyRoute{}, %{
          participant_ref: route.participant_ref,
          service: route.service,
          number: route.number,
          published_at: nil,
          tenant_id: tenant.id,
          definition_revision_id: revision.id
        })

      case repo.insert(changeset) do
        {:ok, stored} ->
          {:cont, {:ok, [stored | stored_routes]}}

        {:error, _changeset} ->
          {:halt, {:error, :telephony_route_insert_failed}}
      end
    end)
    |> case do
      {:ok, stored_routes} -> {:ok, Enum.reverse(stored_routes)}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_stored_revision(repo, tenant_key, definition_id, revision_number) do
    query =
      from(revision in StoredRevision,
        join: definition in assoc(revision, :call_definition),
        join: tenant in assoc(definition, :tenant),
        where:
          tenant.key == ^tenant_key and definition.public_id == ^definition_id and
            revision.revision == ^revision_number,
        select: {definition, revision}
      )

    case repo.one(query) do
      nil -> {:error, :not_found}
      selection -> {:ok, selection}
    end
  end

  defp routes_for_definition(definition_id) do
    from(route in StoredRoute,
      join: revision in assoc(route, :definition_revision),
      where: revision.call_definition_id == ^definition_id
    )
  end

  defp telephony_routes_for_definition(definition_id) do
    from(route in StoredTelephonyRoute,
      join: revision in assoc(route, :definition_revision),
      where: revision.call_definition_id == ^definition_id
    )
  end

  defp to_revision(definition, revision, routes, telephony_routes, tenant_key) do
    published? = definition.published_revision_id == revision.id

    %DefinitionRevision{
      tenant_key: tenant_key,
      definition_id: definition.public_id,
      revision: revision.revision,
      schema_version: revision.schema_version,
      source: revision.source,
      source_digest: revision.source_digest,
      compiled_metadata: revision.compiled_metadata,
      validation_errors: revision.validation_errors,
      routes:
        routes
        |> Enum.map(&to_route(&1, tenant_key, definition.public_id, revision.revision))
        |> Enum.sort_by(& &1.participant_ref),
      telephony_routes:
        telephony_routes
        |> Enum.map(&to_telephony_route(&1, tenant_key, definition.public_id, revision.revision))
        |> Enum.sort_by(& &1.participant_ref),
      published_at: if(published?, do: definition.published_at),
      inserted_at: revision.inserted_at
    }
  end

  defp to_route(route, tenant_key, definition_id, definition_revision) do
    %ParticipantRoute{
      key: route.public_id,
      tenant_key: tenant_key,
      definition_id: definition_id,
      definition_revision: definition_revision,
      participant_ref: route.participant_ref,
      published_at: route.published_at
    }
  end

  defp to_telephony_route(route, tenant_key, definition_id, definition_revision) do
    %TelephonyRoute{
      tenant_key: tenant_key,
      definition_id: definition_id,
      definition_revision: definition_revision,
      participant_ref: route.participant_ref,
      service: route.service,
      number: route.number,
      published_at: route.published_at
    }
  end

  defp scope_telephony_routes(query, {:tenant, tenant_key}) do
    from([_route, tenant, _revision, _definition] in query,
      where: tenant.key == ^tenant_key
    )
  end
end
