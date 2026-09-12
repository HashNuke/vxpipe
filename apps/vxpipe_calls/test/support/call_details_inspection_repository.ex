defmodule Vxpipe.Calls.TestCallDetailsInspectionRepository do
  @moduledoc false

  use Agent

  @behaviour Vxpipe.Calls.CallDetailsInspectionRepository

  alias Vxpipe.Calls.CallDetailsCursor

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        documents: Keyword.get(options, :documents, %{}),
        operations: [],
        revisions: Keyword.get(options, :revisions, %{})
      }
    end)
  end

  def repository(agent), do: {__MODULE__, agent}
  def operations(agent), do: Agent.get(agent, &Enum.reverse(&1.operations))

  @impl true
  def list(agent, tenant_key, call_id, limit, cursor) do
    Agent.get_and_update(agent, fn state ->
      revisions =
        state.revisions
        |> Map.get({tenant_key, call_id}, [])
        |> Enum.sort_by(&{&1.recorded_at, &1.id}, :desc)
        |> after_cursor(cursor)
        |> Enum.take(limit)

      operation = {:list, tenant_key, call_id, limit, cursor_key(cursor)}
      {{:ok, revisions}, %{state | operations: [operation | state.operations]}}
    end)
  end

  @impl true
  def fetch(agent, tenant_key, call_id, publication_id) do
    Agent.get_and_update(agent, fn state ->
      result =
        case Map.fetch(state.documents, {tenant_key, call_id, publication_id}) do
          {:ok, document} -> {:ok, document}
          :error -> {:error, :call_details_not_found}
        end

      operation = {:fetch, tenant_key, call_id, publication_id}
      {result, %{state | operations: [operation | state.operations]}}
    end)
  end

  defp after_cursor(revisions, nil), do: revisions

  defp after_cursor(revisions, %CallDetailsCursor{} = cursor) do
    Enum.filter(revisions, fn revision ->
      {revision.recorded_at, revision.id} < {cursor.recorded_at, cursor.publication_id}
    end)
  end

  defp cursor_key(nil), do: nil
  defp cursor_key(cursor), do: {cursor.recorded_at, cursor.publication_id}
end
