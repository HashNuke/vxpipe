defmodule Vxpipe.Persistence.LatencyRunQuery do
  @moduledoc false
  import Ecto.Query
  alias Vxpipe.Persistence.LatencyRecordCodec
  alias Vxpipe.Persistence.Schema.{LatencyRun, TurnDiagnostic}

  def fetch(repo, call_id, limit, cursor) do
    query =
      from(run in LatencyRun,
        left_join: turn in TurnDiagnostic,
        on: turn.run_id == run.id,
        where: run.call_id == ^call_id,
        group_by: run.id,
        order_by: run.public_id,
        limit: ^(limit + 1),
        select: {run, count(turn.id)}
      )

    query =
      if cursor, do: from([run, _turn] in query, where: run.public_id > ^cursor), else: query

    {records, overflow} = query |> repo.all() |> Enum.split(limit)

    with {:ok, entries} <- decode(records) do
      cursor = if overflow == [], do: nil, else: List.last(entries).run.id
      {:ok, %{entries: entries, next_cursor: cursor}}
    end
  end

  defp decode(records) do
    Enum.reduce_while(records, {:ok, []}, fn {stored, count}, {:ok, acc} ->
      case LatencyRecordCodec.decode_run(stored.record) do
        {:ok, run} -> {:cont, {:ok, [%{run: run, stored_turns: count} | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end
end
