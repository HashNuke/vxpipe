defmodule Vxpipe.Calls.TestMemoryRepository do
  use Agent

  def start_link(_options) do
    Agent.start_link(fn ->
      %{tenants: %{}, keys: %{}, definitions: %{}, routes: %{}, calls: %{}, tokens: %{}, admissions: %{}}
    end)
  end

  def credential_repository(agent), do: {__MODULE__, agent}
  def definition_repository(agent), do: {__MODULE__, agent}
  def call_repository(agent), do: {__MODULE__, agent}

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

  def insert_prepared_call(agent, call, token) do
    Agent.get_and_update(agent, fn state ->
      cond do
        Map.has_key?(state.calls, {call.tenant_key, call.id}) ->
          {{:error, :call_id_conflict}, state}

        Map.has_key?(state.tokens, token.digest) ->
          {{:error, :join_token_conflict}, state}

        true ->
          next_state = %{
            state
            | calls: Map.put(state.calls, {call.tenant_key, call.id}, call),
              tokens: Map.put(state.tokens, token.digest, token)
          }

          {{:ok, call, token}, next_state}
      end
    end)
  end

  def fetch_call(agent, tenant_key, call_id) do
    Agent.get(agent, fn state -> Map.fetch(state.calls, {tenant_key, call_id}) end)
  end

  def issue_join_token(agent, tenant_key, call_id, participant_key, token) do
    Agent.get_and_update(agent, fn state ->
      with {:ok, call} <- Map.fetch(state.calls, {tenant_key, call_id}),
           {:ok, participant_ref} <- Map.fetch(call.participant_routes, participant_key),
           :ok <- token_binding(token, tenant_key, call_id, participant_key, participant_ref),
           :ok <- admission_available(state, call, participant_ref),
           false <- Map.has_key?(state.tokens, token.digest) do
        {{:ok, token}, %{state | tokens: Map.put(state.tokens, token.digest, token)}}
      else
        :error -> {{:error, :not_found}, state}
        true -> {{:error, :join_token_conflict}, state}
        {:error, _reason} = error -> {error, state}
      end
    end)
  end

  def claim_join_token(agent, digest, expected_scope, now) do
    Agent.get_and_update(agent, fn state ->
      with {:ok, token} <- Map.fetch(state.tokens, digest),
           :ok <- expected_scope(token, expected_scope),
           :ok <- token_available(token, now),
           {:ok, call} <- Map.fetch(state.calls, {token.tenant_key, token.call_id}),
           :ok <- admission_available(state, call, token.participant_ref) do
        consumed = %{token | consumed_at: now}
        call = if call.state == :prepared, do: %{call | state: :admitting}, else: call
        participant = Map.fetch!(call.plan.participants, token.participant_ref)

        claim = %Vxpipe.Calls.AdmissionClaim{
          call: call,
          token_id: token.id,
          participant_key: token.participant_key,
          participant_ref: token.participant_ref,
          participant_id: participant.participant_id,
          accepted_at: now
        }

        admission = %{
          call_id: call.id,
          participant_ref: token.participant_ref,
          participant_key: token.participant_key,
          token_id: token.id,
          accepted_at: now
        }

        next_state = %{
          state
          | calls: Map.put(state.calls, {call.tenant_key, call.id}, call),
            tokens: Map.put(state.tokens, digest, consumed),
            admissions: Map.put(state.admissions, {call.id, token.participant_ref}, admission)
        }

        {{:ok, claim}, next_state}
      else
        :error -> {{:error, :token_not_found}, state}
        {:error, _reason} = error -> {error, state}
      end
    end)
  end

  def admissions(agent), do: Agent.get(agent, &Map.values(&1.admissions))

  defp routes_for(state, tenant_key, definition_id, revision_number) do
    state.routes
    |> Map.values()
    |> Enum.filter(fn route ->
      route.tenant_key == tenant_key and route.definition_id == definition_id and
        route.definition_revision == revision_number
    end)
    |> Enum.sort_by(& &1.participant_ref)
  end

  defp token_binding(token, tenant_key, call_id, participant_key, participant_ref) do
    if token.tenant_key == tenant_key and token.call_id == call_id and
         token.participant_key == participant_key and token.participant_ref == participant_ref,
      do: :ok,
      else: {:error, :token_scope_mismatch}
  end

  defp expected_scope(token, expected_scope) do
    if token.tenant_key == expected_scope.tenant_key and token.call_id == expected_scope.call_id and
         token.participant_key == expected_scope.participant_key,
      do: :ok,
      else: {:error, :token_scope_mismatch}
  end

  defp token_available(%{consumed_at: %DateTime{}}, _now),
    do: {:error, :token_already_claimed}

  defp token_available(token, now) do
    if DateTime.compare(now, token.expires_at) == :lt,
      do: :ok,
      else: {:error, :token_expired}
  end

  defp admission_available(state, call, participant_ref) do
    cond do
      call.state in [:ended, :failed] -> {:error, :call_unavailable}
      Map.has_key?(state.admissions, {call.id, participant_ref}) ->
        {:error, :participant_admission_unavailable}

      call.state == :prepared and participant_ref != call.entry_caller ->
        {:error, :participant_admission_unavailable}

      call.state == :admitting ->
        {:error, :participant_admission_pending}

      true ->
        :ok
    end
  end
end
