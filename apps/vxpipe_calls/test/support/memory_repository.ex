defmodule Vxpipe.Calls.TestMemoryRepository do
  use Agent

  def start_link(_options) do
    Agent.start_link(fn -> %{tenants: %{}, keys: %{}, definitions: %{}, routes: %{}} end)
  end

  def credential_repository(agent), do: {__MODULE__, agent}
  def definition_repository(agent), do: {__MODULE__, agent}

  def bootstrap_tenant(agent, tenant, api_key) do
    Agent.get_and_update(agent, fn state ->
      if Map.has_key?(state.tenants, tenant.key) do
        {{:error, :tenant_key_conflict}, state}
      else
        keys = Map.put(state.keys, {tenant.key, api_key.id}, api_key)
        {{:ok, {tenant, api_key}}, %{state | tenants: Map.put(state.tenants, tenant.key, tenant), keys: keys}}
      end
    end)
  end

  def insert_api_key(agent, tenant_key, api_key) do
    Agent.get_and_update(agent, fn state ->
      cond do
        not Map.has_key?(state.tenants, tenant_key) ->
          {{:error, :tenant_not_found}, state}

        Map.has_key?(state.keys, {tenant_key, api_key.id}) ->
          {{:error, :api_key_id_conflict}, state}

        true ->
          {{:ok, api_key},
           %{state | keys: Map.put(state.keys, {tenant_key, api_key.id}, api_key)}}
      end
    end)
  end

  def fetch_tenant(agent, tenant_key) do
    Agent.get(agent, fn state -> Map.fetch(state.tenants, tenant_key) end)
  end

  def fetch_api_key(agent, tenant_key, digest) do
    Agent.get(agent, fn state ->
      Enum.find_value(state.keys, {:error, :not_found}, fn
        {{^tenant_key, _id}, %{digest: ^digest} = api_key} -> {:ok, api_key}
        _entry -> nil
      end)
    end)
  end

  def revoke_api_key(agent, tenant_key, api_key_id, revoked_at) do
    Agent.get_and_update(agent, fn state ->
      case Map.fetch(state.keys, {tenant_key, api_key_id}) do
        {:ok, api_key} ->
          revoked = %{api_key | revoked_at: api_key.revoked_at || revoked_at}
          {{:ok, revoked}, %{state | keys: Map.put(state.keys, {tenant_key, api_key_id}, revoked)}}

        :error ->
          {{:error, :not_found}, state}
      end
    end)
  end

  def next_revision(agent, tenant_key, definition_id) do
    Agent.get(agent, fn state ->
      revisions = Map.get(state.definitions, {tenant_key, definition_id}, %{})
      {:ok, revisions |> Map.keys() |> Enum.max(fn -> 0 end) |> Kernel.+(1)}
    end)
  end

  def insert_revision(agent, tenant_key, revision, routes) do
    Agent.get_and_update(agent, fn state ->
      key = {tenant_key, revision.definition_id}
      revisions = Map.get(state.definitions, key, %{})

      if Map.has_key?(revisions, revision.revision) do
        {{:error, :revision_conflict}, state}
      else
        definitions = Map.put(state.definitions, key, Map.put(revisions, revision.revision, revision))

        route_records =
          Map.new(routes, fn route ->
            {route.key, route}
          end)

        {{:ok, %{revision | routes: routes}},
         %{state | definitions: definitions, routes: Map.merge(state.routes, route_records)}}
      end
    end)
  end

  def fetch_revision(agent, tenant_key, definition_id, revision_number) do
    Agent.get(agent, fn state ->
      with {:ok, revisions} <- Map.fetch(state.definitions, {tenant_key, definition_id}),
           {:ok, revision} <- Map.fetch(revisions, revision_number) do
        routes = routes_for(state, tenant_key, definition_id, revision_number)
        {:ok, %{revision | routes: routes}}
      else
        :error -> {:error, :not_found}
      end
    end)
  end

  def publish_revision(agent, tenant_key, definition_id, revision_number, published_at) do
    Agent.get_and_update(agent, fn state ->
      with {:ok, revisions} <- Map.fetch(state.definitions, {tenant_key, definition_id}),
           {:ok, revision} <- Map.fetch(revisions, revision_number) do
        routes =
          Map.new(state.routes, fn {route_key, route} ->
            same_definition? =
              route.tenant_key == tenant_key and route.definition_id == definition_id

            route =
              cond do
                same_definition? and route.definition_revision == revision_number ->
                  %{route | published_at: published_at}

                same_definition? ->
                  %{route | published_at: nil}

                true ->
                  route
              end

            {route_key, route}
          end)

        published = %{revision | published_at: revision.published_at || published_at}
        definitions = Map.put(state.definitions, {tenant_key, definition_id}, Map.put(revisions, revision_number, published))
        result_routes = routes_for(%{state | routes: routes}, tenant_key, definition_id, revision_number)

        {{:ok, %{published | routes: result_routes}},
         %{state | definitions: definitions, routes: routes}}
      else
        :error -> {{:error, :not_found}, state}
      end
    end)
  end

  def resolve_route(agent, tenant_key, route_key) do
    Agent.get(agent, fn state ->
      case Map.fetch(state.routes, route_key) do
        {:ok, %{tenant_key: ^tenant_key, published_at: %DateTime{}} = route} -> {:ok, route}
        _missing_or_draft -> {:error, :route_unavailable}
      end
    end)
  end

  def stored_api_keys(agent) do
    Agent.get(agent, &Map.values(&1.keys))
  end

  defp routes_for(state, tenant_key, definition_id, revision_number) do
    state.routes
    |> Map.values()
    |> Enum.filter(fn route ->
      route.tenant_key == tenant_key and route.definition_id == definition_id and
        route.definition_revision == revision_number
    end)
    |> Enum.sort_by(& &1.participant_ref)
  end
end
