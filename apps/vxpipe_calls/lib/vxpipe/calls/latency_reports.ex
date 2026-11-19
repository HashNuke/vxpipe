defmodule Vxpipe.Calls.LatencyReports do
  @moduledoc "Authorized, bounded reads of optional diagnostics, independent of call history."
  alias Vxpipe.Calls.{CallReadAccess, Repositories}
  alias Vxpipe.Calls.Diagnostics.Coverage

  def fetch(authority, call_id, options) when is_list(options) do
    with {:ok, tenant} <- CallReadAccess.tenant_key(authority, :invalid_latency_request),
         :ok <- identifier(call_id),
         {:ok, limit, cursor} <- page(options),
         {:ok, repository} <- Repositories.fetch(options, :latency_repository),
         {:ok, runs} <-
           Repositories.call(repository, :list_runs, [tenant, call_id, limit, cursor]),
         {:ok, summary} <- Repositories.call(repository, :summarize, [tenant, call_id]) do
      now = DateTime.utc_now()

      entries =
        Enum.map(runs.entries, fn entry ->
          %{
            run: entry.run,
            coverage: Coverage.describe(entry.run, entry.stored_turns, now)
          }
        end)

      {:ok, %{entries: entries, next_cursor: runs.next_cursor, summary: summary}}
    end
  end

  def fetch(_authority, _call_id, _options), do: {:error, :invalid_latency_request}

  def turns(authority, call_id, run_id, options) when is_list(options) do
    with {:ok, tenant} <- CallReadAccess.tenant_key(authority, :invalid_latency_request),
         :ok <- identifier(call_id),
         :ok <- identifier(run_id),
         {:ok, limit, cursor} <- page(options),
         {:ok, repository} <- Repositories.fetch(options, :latency_repository),
         {:ok, _run} <- Repositories.call(repository, :fetch_run, [tenant, call_id, run_id]),
         {:ok, turns} <-
           Repositories.call(repository, :list_turns, [tenant, call_id, run_id, limit, cursor]) do
      # A full page may have an empty successor. Never exceed the port's 100-row
      # bound just to detect overflow; the next request resolves that case.
      next_cursor = if length(turns) == limit, do: List.last(turns).turn_id
      {:ok, %{entries: turns, next_cursor: next_cursor}}
    end
  end

  def turns(_authority, _call_id, _run_id, _options), do: {:error, :invalid_latency_request}

  defp page(options) do
    limit = Keyword.get(options, :limit, 50)
    cursor = Keyword.get(options, :cursor)

    with true <- is_integer(limit) and limit in 1..100,
         :ok <- if(cursor == nil, do: :ok, else: identifier(cursor)) do
      {:ok, limit, cursor}
    else
      _ -> {:error, :invalid_latency_request}
    end
  end

  defp identifier(value) when is_binary(value) and byte_size(value) in 1..256, do: :ok
  defp identifier(_value), do: {:error, :invalid_latency_request}
end
