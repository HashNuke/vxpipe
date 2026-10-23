defmodule Vxpipe.Calls.CallClaims do
  @moduledoc "Published-spec call preparation with tenant-wide idempotent claims."

  alias Vxpipe.CallEngine.CallSpec

  alias Vxpipe.Calls.{
    CallManagementAuthorization,
    CanonicalJSON,
    CallSpecCredentials,
    PreparedCallFactory,
    PreparedCall,
    Principal,
    Repositories,
    TelephonyPlanBindings,
    TelephonyServices
  }

  def claim(actor, tenant, id, variables, to, key, options) when is_list(options) do
    with :ok <- CallManagementAuthorization.authorize(actor, tenant),
         :ok <- valid_id(id) do
      do_claim(tenant, id, variables, to, key, options, :any)
    end
  end

  def claim(_actor, _tenant, _id, _variables, _to, _key, _options),
    do: {:error, :invalid_outgoing_call}

  # Preserve the original principal-only outgoing contract and its direction guard.
  def claim_outgoing(%Principal{} = actor, id, variables, to, key, options)
      when is_list(options) do
    with :ok <- authorize(actor),
         do: do_claim(actor.tenant_key, id, variables, to, key, options, :outgoing)
  end

  def claim_outgoing(_actor, _id, _variables, _to, _key, _options),
    do: {:error, :invalid_outgoing_call}

  defp do_claim(tenant, id, variables, to, key, options, mode)
       when is_binary(id) and is_map(variables) and (is_nil(to) or is_binary(to)) do
    with :ok <- valid_key(key),
         {:ok, repository} <- Repositories.fetch(options, :call_repository),
         {:ok, digest} <- digest(id, variables, to, key) do
      case existing(repository, tenant, key, digest) do
        :new ->
          prepare(
            tenant,
            id,
            %{variables: variables, to: to, key: key, digest: digest},
            repository,
            options,
            mode
          )

        result ->
          result
      end
    end
  end

  defp do_claim(_tenant, _id, _variables, _to, _key, _options, _mode),
    do: {:error, :invalid_outgoing_call}

  defp prepare(tenant, id, request, repository, options, mode) do
    with {:ok, specifications} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, %{tenant_key: ^tenant, call_spec_id: ^id} = revision} <-
           Repositories.call(specifications, :fetch_published_revision, [tenant, id]),
         :ok <- expected_revision(revision, options),
         {:ok, transport} <- transport(revision, mode),
         {:ok, call} <-
           PreparedCallFactory.build(
             revision,
             request.variables,
             transport,
             Keyword.put(options, :outgoing_to, request.to)
           ),
         {:ok, call} <- admission(call, options) do
      call = %{call | idempotency_key: request.key, idempotency_digest: request.digest}

      authorize = fn ->
        CallSpecCredentials.with_active(revision, call.plan, options, fn -> {:ok, :authorized} end)
      end

      Repositories.call(repository, :claim_call, [call, authorize])
    else
      {:ok, _invalid} -> {:error, :call_spec_revision_not_found}
      error -> error
    end
  end

  defp expected_revision(revision, options) do
    case Keyword.get(options, :expected_call_spec_revision) do
      nil -> :ok
      expected when expected == revision.revision -> :ok
      _changed -> {:error, :call_spec_revision_conflict}
    end
  end

  defp transport(revision, mode) do
    with {:ok, spec} <-
           CallSpec.new(revision.source,
             resource_id: revision.call_spec_id,
             revision: revision.revision
           ) do
      case {spec.direction, mode, Map.fetch!(spec.participants, spec.entry_caller).connection} do
        {:outgoing, _, _connection} -> {:ok, :telephony}
        {_direction, :outgoing, _connection} -> {:error, :call_spec_not_outgoing}
        {:incoming, :any, %{service: :web, mode: :receive, admission: :start_call}} -> {:ok, :web}
        _unsupported -> {:error, :unsupported_call_entry}
      end
    end
  end

  defp admission(%PreparedCall{plan: %{direction: :outgoing}} = call, options) do
    with {:ok, from} <- caller_id(call.plan, options),
         do:
           {:ok,
            %{
              call
              | state: :admitting,
                to_number: callee(call.plan).connection.number,
                from_number: from
            }}
  end

  defp admission(call, _options), do: {:ok, call}

  defp valid_id(id) when is_binary(id) and byte_size(id) in 1..128 do
    if String.valid?(id) and not String.contains?(id, [<<0>>, "\n", "\r"]),
      do: :ok,
      else: {:error, :invalid_outgoing_call}
  end

  defp valid_id(_id), do: {:error, :invalid_outgoing_call}

  defp callee(plan), do: Map.fetch!(plan.participants, plan.entry_caller)

  # The caller ID this call was admitted with; publication and the claim lock below
  # guarantee the service has one.
  defp caller_id(plan, options) do
    case TelephonyServices.resolve(plan.tenant_id, callee(plan).connection.service, options) do
      {:ok, %{service: %{outbound_number: number}}} when is_binary(number) -> {:ok, number}
      _unavailable -> TelephonyPlanBindings.caller_id_missing(callee_service_path(plan))
    end
  end

  defp callee_service_path(plan), do: ["participants", plan.entry_caller, "connection", "service"]

  defp existing(_repository, _tenant, nil, _digest), do: :new

  defp existing(repository, tenant, key, digest) do
    case Repositories.call(repository, :fetch_call_by_key, [tenant, key]) do
      {:ok,
       %PreparedCall{tenant_key: ^tenant, idempotency_key: ^key, idempotency_digest: ^digest} =
           call} ->
        {:duplicate, call}

      {:ok, _call} ->
        {:error, :idempotency_conflict}

      {:error, :not_found} ->
        :new

      {:error, _reason} = error ->
        error
    end
  end

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :not_authorized}
  end

  defp valid_key(nil), do: :ok

  defp valid_key(key) when is_binary(key) and byte_size(key) in 1..256 do
    if String.valid?(key) and String.trim(key) != "",
      do: :ok,
      else: {:error, :invalid_idempotency_key}
  end

  defp valid_key(_key), do: {:error, :invalid_idempotency_key}

  defp digest(_id, _variables, _to, nil), do: {:ok, nil}

  defp digest(id, variables, to, _key) do
    # `to` joins the digest only when present, so keys stored before it existed still replay.
    request = %{"call_spec_id" => id, "initial_variables" => variables}
    request = if is_nil(to), do: request, else: Map.put(request, "to", to)
    value = CanonicalJSON.encode!(request)

    {:ok, :crypto.hash(:sha256, value)}
  rescue
    _error -> {:error, :invalid_outgoing_call}
  end
end
