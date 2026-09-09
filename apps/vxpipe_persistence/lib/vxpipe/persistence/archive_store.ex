defmodule Vxpipe.Persistence.ArchiveStore do
  @moduledoc "Ecto adapter for immutable private call-history projections."

  @behaviour Vxpipe.Calls.ArchiveRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallFact, VariableSnapshot, VariableSnapshotHistory}
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.CallFact, as: StoredFact
  alias Vxpipe.Persistence.Schema.VariableSnapshot, as: StoredSnapshot

  @impl true
  def store_call_fact(repo, %CallFact{} = fact) do
    repo.transaction(fn ->
      with %Call{} = call <- fetch_call(repo, fact, lock: "FOR UPDATE"),
           :ok <- archive_available(call),
           :ok <- fact_incarnation_matches(repo, call, fact),
           {:ok, stored} <- insert_or_deduplicate_fact(repo, call, fact),
           {:ok, archived} <- to_call_fact(stored, fact.tenant_key, call.public_id) do
        archived
      else
        nil -> repo.rollback(:call_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:call_fact_insert_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def fetch_call_facts(repo, tenant_key, call_id) do
    query =
      from call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: call

    case repo.one(query) do
      nil ->
        {:error, :call_not_found}

      call ->
        call.id
        |> fact_query()
        |> repo.all()
        |> convert_facts(tenant_key, call_id)
    end
  end

  @impl true
  def store_variable_snapshot(repo, %VariableSnapshot{} = snapshot) do
    repo.transaction(fn ->
      with %Call{} = call <- fetch_call(repo, snapshot, lock: "FOR UPDATE"),
           :ok <- archive_available(call),
           :ok <- incarnation_matches(repo, call, snapshot),
           {:ok, stored} <- insert_or_deduplicate(repo, call, snapshot),
           {:ok, _call} <- advance_latest(repo, call, stored),
           {:ok, archived} <- to_variable_snapshot(stored, snapshot.tenant_key, call.public_id) do
        archived
      else
        nil -> repo.rollback(:call_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:variable_snapshot_insert_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def fetch_variable_snapshots(repo, tenant_key, call_id) do
    query =
      from call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: call

    case repo.one(query) do
      nil ->
        {:error, :call_not_found}

      call ->
        snapshots =
          repo.all(
            from snapshot in StoredSnapshot,
              where: snapshot.call_id == ^call.id,
              order_by: [asc: snapshot.global_revision, asc: snapshot.occurred_at, asc: snapshot.id]
          )

        with {:ok, snapshots} <- convert_snapshots(snapshots, tenant_key, call_id),
             {:ok, latest} <- fetch_latest(repo, call, tenant_key, call_id) do
          {:ok, %VariableSnapshotHistory{snapshots: snapshots, latest: latest}}
        end
    end
  end

  defp fetch_call(repo, snapshot, options) do
    query =
      from call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^snapshot.tenant_key and call.public_id == ^snapshot.call_id,
        select: call

    repo.one(with_lock(query, options))
  end

  defp fact_query(call_id) do
    from fact in StoredFact,
      where: fact.call_id == ^call_id,
      order_by: [asc: fact.sequence, asc: fact.occurred_at, asc: fact.id]
  end

  defp with_lock(query, options) do
    case Keyword.get(options, :lock) do
      nil -> query
      "FOR UPDATE" -> lock(query, "FOR UPDATE")
    end
  end

  defp archive_available(%Call{state: state}) when state in [:admitting, :running, :ended],
    do: :ok

  defp archive_available(_call), do: {:error, :call_not_started}

  defp incarnation_matches(repo, call, snapshot) do
    existing_incarnation =
      repo.one(
        from stored in StoredSnapshot,
          where: stored.call_id == ^call.id,
          select: stored.incarnation_id,
          limit: 1
      )

    expected_incarnation = call.incarnation_id || existing_incarnation

    if is_nil(expected_incarnation) or expected_incarnation == snapshot.incarnation_id,
      do: :ok,
      else: {:error, :call_incarnation_mismatch}
  end

  defp fact_incarnation_matches(repo, call, fact) do
    existing_incarnation =
      repo.one(
        from stored in StoredFact,
          where: stored.call_id == ^call.id,
          select: stored.incarnation_id,
          limit: 1
      )

    expected_incarnation = call.incarnation_id || existing_incarnation

    if is_nil(expected_incarnation) or expected_incarnation == fact.incarnation_id,
      do: :ok,
      else: {:error, :call_incarnation_mismatch}
  end

  defp insert_or_deduplicate_fact(repo, call, fact) do
    case repo.one(
           from stored in StoredFact,
             where: stored.call_id == ^call.id and stored.public_id == ^fact.id
         ) do
      nil -> insert_fact(repo, call, fact)
      stored -> deduplicate_fact(stored, fact, fact.tenant_key, call.public_id)
    end
  end

  defp insert_fact(repo, call, fact) do
    case repo.insert(fact_changeset(call, fact)) do
      {:ok, stored} ->
        {:ok, stored}

      {:error, changeset} ->
        if sequence_conflict?(changeset),
          do: {:error, :call_fact_sequence_conflict},
          else: {:error, changeset}
    end
  end

  defp deduplicate_fact(stored, fact, tenant_key, call_id) do
    case to_call_fact(stored, tenant_key, call_id) do
      {:ok, ^fact} -> {:ok, stored}
      {:ok, _different} -> {:error, :call_fact_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp fact_changeset(call, fact) do
    StoredFact.changeset(%StoredFact{}, %{
      public_id: fact.id,
      call_id: call.id,
      kind: Atom.to_string(fact.kind),
      sequence: fact.sequence,
      room_id: fact.room_id,
      incarnation_id: fact.incarnation_id,
      participant_id: fact.participant_id,
      activation_id: fact.activation_id,
      source_participant_id: fact.source_participant_id,
      connection_id: fact.connection_id,
      command_id: fact.command_id,
      correlation_id: fact.correlation_id,
      tool_call_id: fact.tool_call_id,
      public_sequence: fact.public_sequence,
      occurred_at: fact.occurred_at,
      source_policy: fact.source_policy,
      payload: fact.payload
    })
  end

  defp to_call_fact(stored, tenant_key, call_id) do
    CallFact.new(
      id: stored.public_id,
      kind: String.to_existing_atom(stored.kind),
      sequence: stored.sequence,
      tenant_key: tenant_key,
      call_id: call_id,
      room_id: stored.room_id,
      incarnation_id: stored.incarnation_id,
      participant_id: stored.participant_id,
      activation_id: stored.activation_id,
      source_participant_id: stored.source_participant_id,
      connection_id: stored.connection_id,
      command_id: stored.command_id,
      correlation_id: stored.correlation_id,
      tool_call_id: stored.tool_call_id,
      public_sequence: stored.public_sequence,
      occurred_at: stored.occurred_at,
      source_policy: stored.source_policy,
      payload: stored.payload
    )
  rescue
    ArgumentError -> {:error, :invalid_call_fact}
  end

  defp convert_facts(facts, tenant_key, call_id) do
    Enum.reduce_while(facts, {:ok, []}, fn stored, {:ok, converted} ->
      case to_call_fact(stored, tenant_key, call_id) do
        {:ok, fact} -> {:cont, {:ok, [fact | converted]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, converted} -> {:ok, Enum.reverse(converted)}
      {:error, _reason} = error -> error
    end
  end

  defp insert_or_deduplicate(repo, call, snapshot) do
    case repo.one(
           from stored in StoredSnapshot,
             where: stored.call_id == ^call.id and stored.public_id == ^snapshot.id
         ) do
      nil -> insert_snapshot(repo, call, snapshot)
      stored -> deduplicate(stored, snapshot, snapshot.tenant_key, call.public_id)
    end
  end

  defp insert_snapshot(repo, call, snapshot) do
    case repo.insert(snapshot_changeset(call, snapshot)) do
      {:ok, stored} ->
        {:ok, stored}

      {:error, changeset} ->
        if revision_conflict?(changeset),
          do: {:error, :variable_snapshot_revision_conflict},
          else: {:error, changeset}
    end
  end

  defp deduplicate(stored, snapshot, tenant_key, call_id) do
    case to_variable_snapshot(stored, tenant_key, call_id) do
      {:ok, ^snapshot} -> {:ok, stored}
      {:ok, _different} -> {:error, :variable_snapshot_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp advance_latest(repo, call, stored) do
    current_revision =
      case call.latest_variables_snapshot_id do
        nil -> nil
        id -> repo.one(from snapshot in StoredSnapshot, where: snapshot.id == ^id, select: snapshot.global_revision)
      end

    if is_nil(current_revision) or stored.global_revision > current_revision do
      call
      |> Call.latest_variables_snapshot_changeset(stored.id)
      |> repo.update()
    else
      {:ok, call}
    end
  end

  defp snapshot_changeset(call, snapshot) do
    StoredSnapshot.changeset(%StoredSnapshot{}, %{
      public_id: snapshot.id,
      call_id: call.id,
      kind: snapshot.kind,
      room_id: snapshot.room_id,
      incarnation_id: snapshot.incarnation_id,
      global_revision: snapshot.global_revision,
      sections: encode_sections(snapshot.sections),
      source_policy: snapshot.source_policy,
      command_id: snapshot.command_id,
      participant_id: snapshot.participant_id,
      activation_id: snapshot.activation_id,
      source_participant_id: snapshot.source_participant_id,
      correlation_id: snapshot.correlation_id,
      tool_call_id: snapshot.tool_call_id,
      section: snapshot.section,
      section_revision: snapshot.section_revision,
      occurred_at: snapshot.occurred_at
    })
  end

  defp encode_sections(sections) do
    Map.new(sections, fn {name, section} ->
      {name, %{"revision" => section.revision, "value" => section.value}}
    end)
  end

  defp to_variable_snapshot(stored, tenant_key, call_id) do
    VariableSnapshot.new(
      id: stored.public_id,
      kind: stored.kind,
      tenant_key: tenant_key,
      call_id: call_id,
      room_id: stored.room_id,
      incarnation_id: stored.incarnation_id,
      global_revision: stored.global_revision,
      sections: decode_sections(stored.sections),
      source_policy: stored.source_policy,
      occurred_at: stored.occurred_at,
      command_id: stored.command_id,
      participant_id: stored.participant_id,
      activation_id: stored.activation_id,
      source_participant_id: stored.source_participant_id,
      correlation_id: stored.correlation_id,
      tool_call_id: stored.tool_call_id,
      section: stored.section,
      section_revision: stored.section_revision
    )
  end

  defp decode_sections(sections) do
    Map.new(sections, fn {name, section} ->
      {name,
       %{
         revision: Map.fetch!(section, "revision"),
         value: Map.get(section, "value")
       }}
    end)
  end

  defp convert_snapshots(snapshots, tenant_key, call_id) do
    Enum.reduce_while(snapshots, {:ok, []}, fn stored, {:ok, converted} ->
      case to_variable_snapshot(stored, tenant_key, call_id) do
        {:ok, snapshot} -> {:cont, {:ok, [snapshot | converted]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, converted} -> {:ok, Enum.reverse(converted)}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_latest(_repo, %Call{latest_variables_snapshot_id: nil}, _tenant_key, _call_id),
    do: {:ok, nil}

  defp fetch_latest(repo, call, tenant_key, call_id) do
    case repo.get(StoredSnapshot, call.latest_variables_snapshot_id) do
      nil -> {:error, :latest_variable_snapshot_not_found}
      stored -> to_variable_snapshot(stored, tenant_key, call_id)
    end
  end

  defp revision_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_message, options}} ->
        Keyword.get(options, :constraint_name) ==
          "call_variable_snapshots_call_incarnation_revision_index"
    end)
  end

  defp sequence_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_message, options}} ->
        Keyword.get(options, :constraint_name) ==
          "call_facts_call_incarnation_sequence_index"
    end)
  end
end
