defmodule Vxpipe.Calls.TestInspectionRepository do
  use Agent

  @behaviour Vxpipe.Calls.InspectionRepository

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        calls: Keyword.get(options, :calls, []),
        history: Keyword.get(options, :history, %{}),
        operations: []
      }
    end)
  end

  def repository(server), do: {__MODULE__, server}
  def operations(server), do: Agent.get(server, &Enum.reverse(&1.operations))

  @impl true
  def list_calls(server, tenant_key, limit, cursor) do
    Agent.get_and_update(server, fn state ->
      calls =
        state.calls
        |> Enum.filter(&(&1.tenant_key == tenant_key))
        |> Enum.sort_by(&{&1.created_at, &1.id}, :desc)
        |> after_cursor(cursor)
        |> Enum.take(limit)

      operation = {:list_calls, tenant_key, limit, cursor_value(cursor)}
      {{:ok, calls}, %{state | operations: [operation | state.operations]}}
    end)
  end

  @impl true
  def fetch_call(server, tenant_key, call_id) do
    Agent.get_and_update(server, fn state ->
      result =
        case Enum.find(state.calls, &(&1.tenant_key == tenant_key and &1.id == call_id)) do
          nil -> {:error, :call_not_found}
          call -> {:ok, call}
        end

      {result, %{state | operations: [{:fetch_call, tenant_key, call_id} | state.operations]}}
    end)
  end

  @impl true
  def list_history_records(server, tenant_key, call_id, limit, cursor) do
    Agent.get_and_update(server, fn state ->
      records =
        state.history
        |> Map.get({tenant_key, call_id}, [])
        |> Enum.sort_by(&Vxpipe.Calls.HistoryCursor.record_key/1, :desc)
        |> history_after_cursor(cursor)
        |> Enum.take(limit)

      operation = {:list_history, tenant_key, call_id, limit, history_cursor_value(cursor)}
      {{:ok, records}, %{state | operations: [operation | state.operations]}}
    end)
  end

  @impl true
  def fetch_archive_status(server, tenant_key, call_id) do
    Agent.get_and_update(server, fn state ->
      facts =
        state.history
        |> Map.get({tenant_key, call_id}, [])
        |> Enum.filter(&match?(%Vxpipe.Calls.CallFact{}, &1))

      result = {:ok, Vxpipe.Calls.ArchiveStatus.from_facts(facts)}
      operation = {:fetch_archive_status, tenant_key, call_id}
      {result, %{state | operations: [operation | state.operations]}}
    end)
  end

  defp after_cursor(calls, nil), do: calls

  defp after_cursor(calls, cursor) do
    Enum.filter(calls, fn call ->
      {call.created_at, call.id} < {cursor.created_at, cursor.call_id}
    end)
  end

  defp cursor_value(nil), do: nil
  defp cursor_value(cursor), do: {cursor.created_at, cursor.call_id}

  defp history_after_cursor(records, nil), do: records

  defp history_after_cursor(records, cursor) do
    cursor_key = Vxpipe.Calls.HistoryCursor.cursor_key(cursor)
    Enum.filter(records, &(Vxpipe.Calls.HistoryCursor.record_key(&1) < cursor_key))
  end

  defp history_cursor_value(nil), do: nil
  defp history_cursor_value(cursor), do: Vxpipe.Calls.HistoryCursor.cursor_key(cursor)
end
