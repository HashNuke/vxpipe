defmodule Vxpipe.Calls.CallCleanupScan do
  @moduledoc "Bounded internal traversal of durable cancellation and managed cleanup work."

  alias Vxpipe.Calls.Repositories

  @maximum_id 9_223_372_036_854_775_807
  @type cursor :: nil | %{after_id: non_neg_integer(), through_id: non_neg_integer()}
  @type page :: %{items: [map()], next_cursor: cursor()}

  def scan(cursor, limit, options) when is_list(options) do
    if valid_request?(cursor, limit),
      do: fetch(cursor, limit, options),
      else: {:error, :invalid_cleanup_scan}
  end

  def scan(_cursor, _limit, _options), do: {:error, :invalid_cleanup_scan}

  @doc false
  def valid_request?(cursor, limit),
    do: is_integer(limit) and limit in 1..100 and valid_cursor?(cursor)

  defp valid_cursor?(nil), do: true

  defp valid_cursor?(%{after_id: after_id, through_id: through_id} = cursor)
       when map_size(cursor) == 2 and is_integer(after_id) and is_integer(through_id),
       do: after_id >= 0 and after_id <= through_id and through_id <= @maximum_id

  defp valid_cursor?(_cursor), do: false

  defp fetch(cursor, limit, options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository),
         {:ok, %{items: items, next_cursor: next} = page} when is_list(items) <-
           Repositories.call(repository, :scan_call_cleanup, [cursor, limit]),
         true <- length(items) <= limit and valid_cursor?(next) do
      {:ok, page}
    else
      _unavailable -> {:error, :call_cleanup_unavailable}
    end
  rescue
    _error -> {:error, :call_cleanup_unavailable}
  catch
    _kind, _reason -> {:error, :call_cleanup_unavailable}
  end
end
