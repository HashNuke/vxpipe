defmodule Vxpipe.Gateway.TestCleanupReconciliationRepository do
  @moduledoc false

  def scan_call_cleanup(observer, cursor, limit) do
    send(observer, {:cleanup_scan, self(), cursor, limit})

    receive do
      {:scan_result, result} -> result
    end
  end

  def complete_call_cleanup(observer, binding, completed_at) do
    send(observer, {:cleanup_replay, self(), binding, completed_at})

    receive do
      :complete ->
        {:ok,
         struct(
           Vxpipe.Calls.PreparedCall,
           Map.to_list(binding)
           |> Keyword.delete(:call_id)
           |> Keyword.put(:id, binding.call_id)
           |> Keyword.merge(
             gateway_cleanup_required: true,
             gateway_cleanup_completed_at: completed_at,
             state: :ended
           )
         )}
    end
  end
end
