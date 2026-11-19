defmodule Vxpipe.Persistence.LatencyStore do
  @moduledoc "Tenant-scoped revisioned diagnostics with call-owned lifecycle and bounded reads."
  @behaviour Vxpipe.Calls.LatencyRepository
  import Ecto.Query
  alias Vxpipe.Calls.{LatencyRun, TurnDiagnostic}
  alias Vxpipe.Persistence.LatencyRecordCodec, as: Codec
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.LatencyRun, as: StoredRun
  alias Vxpipe.Persistence.Schema.TurnDiagnostic, as: StoredTurn

  @run_identity [
    :id,
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :source_epoch,
    :clock_id,
    :schema_version,
    :settings_revision,
    :profile,
    :anchor_utc
  ]

  @impl true
  def put_run(repo, %LatencyRun{} = input) do
    safely(fn ->
      repo.transaction(fn ->
        with {:ok, run} <- LatencyRun.new(Map.from_struct(input)),
             {:ok, call} <- call(repo, run.tenant_key, run.call_id, true),
             :ok <- matching_call(call, run.room_id, run.incarnation_id),
             existing = repo.get_by(StoredRun, call_id: call.id, public_id: run.id),
             :ok <- validate_run_update(existing, run),
             {:ok, _stored} <- save_run(repo, call.id, existing, run) do
          run
        else
          {:error, reason} -> repo.rollback(reason)
        end
      end)
    end)
  end

  @impl true
  def put_turn(repo, tenant_key, call_id, incarnation_id, %TurnDiagnostic{} = input) do
    safely(fn ->
      repo.transaction(fn ->
        with {:ok, turn} <-
               input
               |> Map.from_struct()
               |> Map.drop([:durations_us, :metric_reasons, :quality])
               |> TurnDiagnostic.new(),
             {:ok, call} <- call(repo, tenant_key, call_id, true),
             :ok <- matching_call(call, call.room_id, incarnation_id),
             {:ok, stored_run} <- stored_run(repo, call.id, turn.run_id),
             {:ok, run} <- Codec.decode_run(stored_run.record),
             :ok <- matching_source(run, turn, incarnation_id),
             existing = repo.get_by(StoredTurn, run_id: stored_run.id, turn_id: turn.turn_id),
             :ok <- validate_turn_update(existing, turn),
             {:ok, _stored} <- save_turn(repo, stored_run.id, existing, turn) do
          turn
        else
          {:error, reason} -> repo.rollback(reason)
        end
      end)
    end)
  end

  @impl true
  def fetch_run(repo, tenant_key, call_id, run_id) do
    safely(fn ->
      with {:ok, call} <- call(repo, tenant_key, call_id, false),
           {:ok, stored} <- stored_run(repo, call.id, run_id) do
        Codec.decode_run(stored.record)
      end
    end)
  end

  @impl true
  def list_turns(repo, tenant_key, call_id, run_id, limit, cursor)
      when is_integer(limit) and limit in 1..100 and
             (is_nil(cursor) or (is_binary(cursor) and byte_size(cursor) in 1..256)) do
    safely(fn ->
      with {:ok, call} <- call(repo, tenant_key, call_id, false),
           {:ok, run} <- stored_run(repo, call.id, run_id) do
        query =
          from(t in StoredTurn, where: t.run_id == ^run.id, order_by: t.turn_id, limit: ^limit)

        query = if cursor, do: from(t in query, where: t.turn_id > ^cursor), else: query
        query |> repo.all() |> decode_turns()
      end
    end)
  end

  def list_turns(_repo, _tenant_key, _call_id, _run_id, _limit, _cursor),
    do: {:error, :invalid_page}

  @impl true
  def list_runs(repo, tenant_key, call_id, limit, cursor)
      when is_integer(limit) and limit in 1..100 and
             (is_nil(cursor) or (is_binary(cursor) and byte_size(cursor) in 1..256)) do
    safely(fn ->
      with {:ok, call} <- call(repo, tenant_key, call_id, false) do
        Vxpipe.Persistence.LatencyRunQuery.fetch(repo, call.id, limit, cursor)
      end
    end)
  end

  def list_runs(_repo, _tenant_key, _call_id, _limit, _cursor), do: {:error, :invalid_page}

  @impl true
  def summarize(repo, tenant_key, call_id) do
    safely(fn ->
      with {:ok, call} <- call(repo, tenant_key, call_id, false) do
        Vxpipe.Persistence.LatencySummaryQuery.fetch(repo, call.id)
      end
    end)
  end

  defp call(repo, tenant_key, call_id, lock?) do
    query =
      from(c in Call,
        join: t in Tenant,
        on: t.id == c.tenant_id,
        where: t.key == ^tenant_key and c.public_id == ^call_id,
        select: c
      )

    query = if lock?, do: lock(query, "FOR UPDATE OF c0"), else: query

    case repo.one(query) do
      nil -> {:error, :call_not_found}
      call -> {:ok, call}
    end
  end

  defp matching_call(call, room_id, incarnation_id) do
    cond do
      call.room_id != room_id ->
        {:error, :call_room_mismatch}

      not call.incarnation_binding_verified or call.incarnation_id != incarnation_id ->
        {:error, :call_incarnation_mismatch}

      call.state not in [:admitting, :running, :ended] ->
        {:error, :call_not_started}

      true ->
        :ok
    end
  end

  defp stored_run(repo, call_id, run_id) do
    case repo.get_by(StoredRun, call_id: call_id, public_id: run_id) do
      nil -> {:error, :latency_run_not_found}
      run -> {:ok, run}
    end
  end

  defp matching_source(run, turn, incarnation_id) do
    if run.clock_id == turn.clock_id and run.source_epoch == turn.source_epoch and
         run.incarnation_id == incarnation_id,
       do: :ok,
       else: {:error, :diagnostic_source_mismatch}
  end

  defp validate_run_update(nil, _run), do: :ok

  defp validate_run_update(existing, run) do
    with {:ok, old} <- Codec.decode_run(existing.record),
         :ok <- revision(old, run) do
      cond do
        Map.take(old, @run_identity) != Map.take(run, @run_identity) ->
          {:error, :run_identity_conflict}

        old.state != :running and run.state == :running ->
          {:error, :run_closed}

        DateTime.compare(run.heartbeat_at, old.heartbeat_at) == :lt ->
          {:error, :regressive_run}

        Enum.any?(old.counts, fn {key, value} -> Map.fetch!(run.counts, key) < value end) ->
          {:error, :regressive_run}

        true ->
          :ok
      end
    end
  end

  defp validate_turn_update(nil, _turn), do: :ok

  defp validate_turn_update(existing, turn) do
    with {:ok, old} <- Codec.decode_turn(existing.record),
         :ok <- revision(old, turn) do
      if old.stt_allocation_id == turn.stt_allocation_id,
        do: :ok,
        else: {:error, :turn_identity_conflict}
    end
  end

  defp revision(old, new) do
    cond do
      new.revision < old.revision -> {:error, :stale_revision}
      new.revision == old.revision and old != new -> {:error, :revision_conflict}
      true -> :ok
    end
  end

  defp save_run(repo, call_id, existing, run) do
    attrs = %{
      call_id: call_id,
      public_id: run.id,
      revision: run.revision,
      record: Codec.encode(run),
      profile: Codec.encode(run)["profile"],
      state: Atom.to_string(run.state),
      heartbeat_at: utc_usec(run.heartbeat_at)
    }

    save(repo, existing || %StoredRun{}, attrs)
  end

  defp utc_usec(%DateTime{microsecond: {value, _precision}} = datetime),
    do: %{datetime | microsecond: {value, 6}}

  defp save_turn(repo, run_id, existing, turn) do
    durations = Map.new(turn.durations_us, fn {key, value} -> {Atom.to_string(key), value} end)

    attrs = %{
      run_id: run_id,
      turn_id: turn.turn_id,
      revision: turn.revision,
      record: Codec.encode(turn),
      durations_us: durations,
      quality: Atom.to_string(turn.quality)
    }

    save(repo, existing || %StoredTurn{}, attrs)
  end

  defp save(repo, record, attrs),
    do: record |> Ecto.Changeset.change(attrs) |> repo.insert_or_update()

  defp decode_turns(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, acc} ->
      case Codec.decode_turn(record.record) do
        {:ok, turn} -> {:cont, {:ok, [turn | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, turns} -> {:ok, Enum.reverse(turns)}
      error -> error
    end
  end

  defp safely(fun) do
    fun.()
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :diagnostics_unavailable}
    _error in Ecto.Query.CastError -> {:error, :call_not_found}
  end
end
