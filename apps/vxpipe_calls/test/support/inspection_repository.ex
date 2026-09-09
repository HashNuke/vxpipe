defmodule Vxpipe.Calls.TestInspectionRepository do
  use Agent

  @behaviour Vxpipe.Calls.InspectionRepository

  def start_link(options) do
    Agent.start_link(fn -> %{calls: Keyword.get(options, :calls, []), operations: []} end)
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

  defp after_cursor(calls, nil), do: calls

  defp after_cursor(calls, cursor) do
    Enum.filter(calls, fn call ->
      {call.created_at, call.id} < {cursor.created_at, cursor.call_id}
    end)
  end

  defp cursor_value(nil), do: nil
  defp cursor_value(cursor), do: {cursor.created_at, cursor.call_id}
end
