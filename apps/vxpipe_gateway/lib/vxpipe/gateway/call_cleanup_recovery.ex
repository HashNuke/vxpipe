defmodule Vxpipe.Gateway.CallCleanupRecovery do
  @moduledoc "Recovers durable intent using exact ownership; never reconstructs runtime membership."

  alias Vxpipe.{CallEngine, Calls}

  @keys [:tenant_key, :call_id, :room_id, :incarnation_id]

  def reconcile(
        %{incarnation_binding_verified: true, hangup_requested_at: %DateTime{}} = row,
        options
      ) do
    binding = Map.take(row, @keys)

    if map_size(binding) == 4 and Enum.all?(Map.values(binding), &identifier?/1) do
      recover(row, binding, options)
    else
      :unknown
    end
  rescue
    _error -> :unknown
  catch
    _kind, _reason -> :unknown
  end

  def reconcile(_row, _options), do: :waiting

  defp recover(
         %{gateway_cleanup_required: true, gateway_cleanup_completed_at: %DateTime{} = completed},
         binding,
         options
       ) do
    # Normal cleanup may commit before a later hangup intent. Its tracker can
    # already be retired; replay the durable proof with its original timestamp.
    case Calls.complete_call_cleanup(binding, completed, options) do
      {:ok, _call} -> :replayed
      _unavailable -> :unknown
    end
  end

  defp recover(_row, binding, _options) do
    # Exact stop is safe even if the tracker was lost. That loss remains unknown:
    # only the existing owner or durable archive can establish completion.
    case CallEngine.hangup_call(binding.tenant_key, binding.room_id, binding.incarnation_id) do
      :ok -> :requested
      _unavailable -> :unknown
    end
  end

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..128,
    do: String.valid?(value) and not String.contains?(value, [<<0>>, "\n", "\r"])

  defp identifier?(_value), do: false
end
