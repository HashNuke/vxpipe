defmodule Vxpipe.Persistence.CallStore do
  @moduledoc "Ecto adapter for prepared calls and atomic participant admission."

  @behaviour Vxpipe.Calls.CallRepository

  import Ecto.Query

  alias Ecto.Multi
  alias Vxpipe.Calls.{AdmissionClaim, JoinToken, TelephonyAdmissionClaim}
  alias Vxpipe.Persistence.{PreparedCallRecord, TelephonyCallStore}
  alias Vxpipe.Persistence.Schema.{Admission, Call, CallDefinition, Tenant}
  alias Vxpipe.Persistence.Schema.DefinitionRevision, as: StoredRevision
  alias Vxpipe.Persistence.Schema.JoinToken, as: StoredToken

  @impl true
  def insert_prepared_call(repo, call, token) do
    multi =
      Multi.new()
      |> Multi.run(:selection, fn repo, _changes ->
        fetch_selection(repo, call.tenant_key, call.definition_id, call.definition_revision)
      end)
      |> Multi.insert(:call, fn %{selection: {tenant, _definition, revision}} ->
        PreparedCallRecord.changeset(call, tenant, revision)
      end)
      |> Multi.insert(:token, fn %{
                                   selection: {tenant, _definition, _revision},
                                   call: stored_call
                                 } ->
        token_changeset(token, tenant, stored_call)
      end)

    case repo.transaction(multi) do
      {:ok, %{call: stored_call, token: stored_token, selection: selection}} ->
        with {:ok, loaded_call} <- PreparedCallRecord.load(stored_call, selection) do
          {:ok, loaded_call, to_join_token(stored_token, call.tenant_key, call.id)}
        end

      {:error, :call, changeset, _changes} ->
        if unique_error?(changeset),
          do: {:error, :call_id_conflict},
          else: {:error, :call_insert_failed}

      {:error, :token, changeset, _changes} ->
        if unique_error?(changeset),
          do: {:error, :join_token_conflict},
          else: {:error, :join_token_insert_failed}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_call(repo, tenant_key, call_id) do
    case fetch_stored_call(repo, tenant_key, call_id) do
      nil -> {:error, :not_found}
      {call, selection} -> PreparedCallRecord.load(call, selection)
    end
  end

  @impl true
  def issue_join_token(repo, tenant_key, call_id, participant_key, token) do
    repo.transaction(fn ->
      with {call, selection} <- fetch_stored_call(repo, tenant_key, call_id, lock: "FOR UPDATE"),
           {:ok, participant_ref} <- Map.fetch(call.participant_routes, participant_key),
           :ok <- token_binding(token, tenant_key, call_id, participant_key, participant_ref),
           :ok <- admission_available(repo, call, participant_ref),
           {:ok, stored} <- repo.insert(token_changeset(token, selection_tenant(selection), call)) do
        to_join_token(stored, tenant_key, call_id)
      else
        nil -> repo.rollback(:not_found)
        :error -> repo.rollback(:participant_not_found)
        {:error, %Ecto.Changeset{} = changeset} ->
          reason = if unique_error?(changeset), do: :join_token_conflict, else: :join_token_insert_failed
          repo.rollback(reason)

        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def release_admission(repo, %AdmissionClaim{} = claim, %DateTime{} = released_at) do
    result =
      repo.transaction(fn ->
        case fetch_stored_call(repo, claim.call.tenant_key, claim.call.id, lock: "FOR UPDATE") do
          {call, _selection} ->
            query =
              from(admission in Admission,
                join: token in StoredToken,
                on: token.id == admission.join_token_id,
                where:
                  admission.call_id == ^call.id and
                    admission.participant_ref == ^claim.participant_ref and
                    admission.participant_key == ^claim.participant_key and
                    token.public_id == ^claim.token_id
              )

            case repo.one(query) do
              nil ->
                repo.rollback(:admission_not_found)

              %Admission{released_at: nil} = admission ->
                repo.update!(Ecto.Changeset.change(admission, released_at: released_at))
                :ok

              %Admission{} ->
                :ok
            end

          nil ->
            repo.rollback(:admission_not_found)
        end
      end)

    case result do
      {:ok, :ok} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def claim_incoming_telephony(repo, %TelephonyAdmissionClaim{} = claim, authorize) do
    TelephonyCallStore.claim(repo, claim, authorize)
  end

  @impl true
  def mark_incoming_telephony_started(repo, claim, incarnation_id, started_at) do
    TelephonyCallStore.mark_started(repo, claim, incarnation_id, started_at)
  end

  @impl true
  def mark_incoming_telephony_failed(repo, claim, reason, failed_at) do
    TelephonyCallStore.mark_failed(repo, claim, reason, failed_at)
  end

  @impl true
  def claim_join_token(repo, digest, expected_scope, now) do
    repo.transaction(fn ->
      with %StoredToken{} = token <- fetch_token(repo, digest),
           :ok <- expected_scope(token, expected_scope),
           :ok <- token_available(token, now),
           {call, selection} <- fetch_stored_call_by_id(repo, token.call_id, lock: "FOR UPDATE"),
           :ok <- call_scope(call, selection, token, expected_scope),
           :ok <- admission_available(repo, call, token.participant_ref),
           {:ok, consumed} <- repo.update(StoredToken.consume_changeset(token, now)),
           {:ok, _admission} <- repo.insert(admission_changeset(call, consumed, now)),
           {:ok, call} <- transition_to_admitting(repo, call),
           {:ok, prepared_call} <- PreparedCallRecord.load(call, selection) do
        participant = Map.fetch!(prepared_call.plan.participants, token.participant_ref)

        %AdmissionClaim{
          call: prepared_call,
          token_id: token.public_id,
          participant_key: token.participant_key,
          participant_ref: token.participant_ref,
          participant_id: participant.participant_id,
          accepted_at: now
        }
      else
        nil -> repo.rollback(:token_not_found)
        {:error, %Ecto.Changeset{} = changeset} ->
          reason = if unique_error?(changeset), do: :participant_admission_unavailable, else: :admission_failed
          repo.rollback(reason)

        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def mark_call_started(repo, claim, incarnation_id, started_at) do
    project_lifecycle(repo, claim, fn
      %Call{state: :admitting} = call ->
        repo.update(Call.start_changeset(call, incarnation_id, started_at))

      %Call{state: :running} = call ->
        {:ok, call}

      _call ->
        {:error, :call_unavailable}
    end)
  end

  @impl true
  def mark_call_failed(repo, claim, reason, failed_at) do
    project_lifecycle(repo, claim, fn
      %Call{state: :admitting} = call ->
        repo.update(Call.failure_changeset(call, reason, failed_at))

      %Call{state: :failed} = call ->
        {:ok, call}

      _call ->
        {:error, :call_unavailable}
    end)
  end

  defp fetch_selection(repo, tenant_key, definition_id, revision_number) do
    query =
      from revision in StoredRevision,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        join: tenant in Tenant,
        on: tenant.id == definition.tenant_id,
        where:
          tenant.key == ^tenant_key and definition.public_id == ^definition_id and
            revision.revision == ^revision_number,
        select: {tenant, definition, revision}

    case repo.one(query) do
      nil -> {:error, :definition_revision_not_found}
      selection -> {:ok, selection}
    end
  end

  defp fetch_stored_call(repo, tenant_key, public_id, options \\ []) do
    query =
      from call in Call,
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :definition_revision),
        join: definition in assoc(revision, :call_definition),
        where: tenant.key == ^tenant_key and call.public_id == ^public_id,
        select: {call, {tenant, definition, revision}}

    repo.one(with_lock(query, options))
  end

  defp fetch_stored_call_by_id(repo, id, options) when is_integer(id) do
    query =
      from call in Call,
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :definition_revision),
        join: definition in assoc(revision, :call_definition),
        where: call.id == ^id,
        select: {call, {tenant, definition, revision}}

    repo.one(with_lock(query, options))
  end

  defp with_lock(query, options) do
    case Keyword.get(options, :lock) do
      nil -> query
      "FOR UPDATE" -> lock(query, "FOR UPDATE")
    end
  end

  defp fetch_token(repo, digest) do
    repo.one(from token in StoredToken, where: token.digest == ^digest, lock: "FOR UPDATE")
  end

  defp token_changeset(token, tenant, call) do
    StoredToken.changeset(%StoredToken{}, %{
      public_id: token.id,
      tenant_id: tenant.id,
      call_id: call.id,
      participant_key: token.participant_key,
      participant_ref: token.participant_ref,
      digest: token.digest,
      issued_at: token.issued_at,
      expires_at: token.expires_at,
      consumed_at: token.consumed_at
    })
  end

  defp admission_changeset(call, token, accepted_at) do
    Admission.changeset(%Admission{}, %{
      call_id: call.id,
      join_token_id: token.id,
      participant_key: token.participant_key,
      participant_ref: token.participant_ref,
      accepted_at: accepted_at
    })
  end

  defp transition_to_admitting(repo, %Call{state: :prepared} = call) do
    repo.update(Call.state_changeset(call, :admitting))
  end

  defp transition_to_admitting(_repo, %Call{} = call), do: {:ok, call}

  defp to_join_token(token, tenant_key, call_id) do
    %JoinToken{
      id: token.public_id,
      tenant_key: tenant_key,
      call_id: call_id,
      participant_key: token.participant_key,
      participant_ref: token.participant_ref,
      digest: token.digest,
      issued_at: token.issued_at,
      expires_at: token.expires_at,
      consumed_at: token.consumed_at
    }
  end

  defp token_binding(token, tenant_key, call_id, participant_key, participant_ref) do
    if token.tenant_key == tenant_key and token.call_id == call_id and
         token.participant_key == participant_key and token.participant_ref == participant_ref,
      do: :ok,
      else: {:error, :token_scope_mismatch}
  end

  defp expected_scope(token, expected_scope) do
    if token.participant_key == expected_scope.participant_key,
      do: :ok,
      else: {:error, :token_scope_mismatch}
  end

  defp call_scope(call, {tenant, _definition, _revision}, token, expected_scope) do
    if tenant.key == expected_scope.tenant_key and call.public_id == expected_scope.call_id and
         token.tenant_id == tenant.id and token.call_id == call.id,
      do: :ok,
      else: {:error, :token_scope_mismatch}
  end

  defp token_available(%StoredToken{consumed_at: %DateTime{}}, _now),
    do: {:error, :token_already_claimed}

  defp token_available(token, now) do
    if DateTime.compare(now, token.expires_at) == :lt,
      do: :ok,
      else: {:error, :token_expired}
  end

  defp admission_available(repo, call, participant_ref) do
    already_admitted? =
      repo.exists?(
        from admission in Admission,
          where:
            admission.call_id == ^call.id and admission.participant_ref == ^participant_ref and
              is_nil(admission.released_at)
      )

    cond do
      call.state in [:ended, :failed] -> {:error, :call_unavailable}
      already_admitted? -> {:error, :participant_admission_unavailable}
      call.state == :prepared and participant_ref != call.entry_caller ->
        {:error, :participant_admission_unavailable}

      call.state == :admitting ->
        {:error, :participant_admission_pending}

      true ->
        :ok
    end
  end

  defp selection_tenant({tenant, _definition, _revision}), do: tenant

  defp project_lifecycle(repo, claim, transition) do
    repo.transaction(fn ->
      with {call, selection} <-
             fetch_stored_call(
               repo,
               claim.call.tenant_key,
               claim.call.id,
               lock: "FOR UPDATE"
             ),
           true <- matching_admission?(repo, call, claim),
           {:ok, call} <- transition.(call),
           {:ok, prepared_call} <- PreparedCallRecord.load(call, selection) do
        prepared_call
      else
        nil -> repo.rollback(:not_found)
        false -> repo.rollback(:admission_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:call_projection_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp matching_admission?(repo, call, claim) do
    repo.exists?(
      from admission in Admission,
        join: token in StoredToken,
        on: token.id == admission.join_token_id,
        where:
          admission.call_id == ^call.id and
            admission.participant_ref == ^claim.participant_ref and
            token.public_id == ^claim.token_id
    )
  end

  defp unique_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
      metadata[:constraint] == :unique
    end)
  end
end
