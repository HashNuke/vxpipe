defmodule Vxpipe.Calls.Inspections do
  @moduledoc "Authorized, bounded workflows for inspecting calls."

  alias Vxpipe.Calls.{CallListCursor, CallListPage, Principal, Repositories}

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
end
