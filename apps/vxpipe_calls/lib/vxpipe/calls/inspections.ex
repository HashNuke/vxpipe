defmodule Vxpipe.Calls.Inspections do
  @moduledoc "Authorized, bounded workflows for inspecting calls."

  alias Vxpipe.Calls.{
    CallDetailPage,
    CallFact,
    CallListCursor,
    CallListPage,
    CallTimeline,
    HistoryCursor,
    LiveCallInspection,
    LiveInspectionSource,
    Principal,
    Repositories
  }

  @default_page_size 25
  @maximum_page_size 100

  @spec list_calls(Principal.t(), keyword()) :: {:ok, CallListPage.t()} | {:error, term()}
  def list_calls(%Principal{} = principal, options) when is_list(options) do
    with :ok <- authorize(principal),
         {:ok, limit} <- page_size(options),
         {:ok, cursor} <- cursor(options),
         {:ok, repository} <- Repositories.fetch(options, :inspection_repository),
         {:ok, candidates} <-
           Repositories.call(repository, :list_calls, [
             principal.tenant_key,
             limit + 1,
             cursor
           ]) do
      {:ok, page(candidates, limit)}
    end
  end

  def list_calls(_principal, _options), do: {:error, :invalid_call_list_request}

  @spec inspect_call(Principal.t(), String.t(), keyword()) ::
          {:ok, CallDetailPage.t()} | {:error, term()}
  def inspect_call(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and byte_size(call_id) > 0 and byte_size(call_id) <= 256 and
             is_list(options) do
    with :ok <- authorize(principal),
         {:ok, limit} <- page_size(options),
         {:ok, cursor} <- history_cursor(options),
         {:ok, repository} <- Repositories.fetch(options, :inspection_repository),
         {:ok, call} <-
           Repositories.call(repository, :fetch_call, [principal.tenant_key, call_id]),
         {:ok, archive_status} <-
           Repositories.call(repository, :fetch_archive_status, [principal.tenant_key, call_id]),
         {:ok, candidates} <-
           Repositories.call(repository, :list_history_records, [
             principal.tenant_key,
             call_id,
             limit + 1,
             cursor
           ]) do
      {:ok, detail_page(call, archive_status, candidates, limit)}
    end
  end

  def inspect_call(_principal, _call_id, _options),
    do: {:error, :invalid_call_inspection_request}

  @spec inspect_live_call(Principal.t(), String.t(), keyword()) ::
          {:ok, LiveCallInspection.t()} | {:error, term()}
  def inspect_live_call(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and byte_size(call_id) > 0 and byte_size(call_id) <= 256 and
             is_list(options) do
    with :ok <- authorize(principal),
         {:ok, snapshot} <- LiveInspectionSource.read(options, principal.tenant_key, call_id) do
      LiveCallInspection.from_engine(snapshot, principal.tenant_key, call_id)
    end
  end

  def inspect_live_call(_principal, _call_id, _options),
    do: {:error, :invalid_call_inspection_request}

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :insufficient_scope}
  end

  defp page_size(options) do
    case Keyword.get(options, :limit, @default_page_size) do
      limit when is_integer(limit) and limit > 0 and limit <= @maximum_page_size -> {:ok, limit}
      _invalid -> {:error, :invalid_call_list_request}
    end
  end

  defp cursor(options) do
    case Keyword.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded when is_binary(encoded) -> CallListCursor.decode(encoded)
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp history_cursor(options) do
    case Keyword.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded when is_binary(encoded) -> HistoryCursor.decode(encoded)
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp page(candidates, limit) do
    {calls, overflow} = Enum.split(candidates, limit)

    %CallListPage{
      calls: calls,
      next_cursor: next_cursor(calls, overflow)
    }
  end

  defp next_cursor(_calls, []), do: nil

  defp next_cursor(calls, _overflow) do
    call = List.last(calls)
    CallListCursor.encode(%CallListCursor{created_at: call.created_at, call_id: call.id})
  end

  defp detail_page(call, archive_status, candidates, limit) do
    {records, overflow} = Enum.split(candidates, limit)
    {facts, snapshots} = Enum.split_with(records, &match?(%CallFact{}, &1))

    %CallDetailPage{
      call: call,
      timeline: CallTimeline.project(facts, snapshots, order: :desc),
      next_cursor: next_history_cursor(records, overflow),
      archive_status: archive_status,
      persisted_variable_revision: call.latest_variable_revision
    }
  end

  defp next_history_cursor(_records, []), do: nil

  defp next_history_cursor(records, _overflow) do
    records
    |> List.last()
    |> HistoryCursor.from_record()
    |> HistoryCursor.encode()
  end
end
