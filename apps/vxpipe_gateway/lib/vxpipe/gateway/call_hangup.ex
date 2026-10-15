defmodule Vxpipe.Gateway.CallHangup do
  @moduledoc "Persists cancellation before requesting exact owned shutdown; never invents completion."

  alias Vxpipe.Calls
  alias Vxpipe.Calls.PreparedCall

  alias Vxpipe.Gateway.{
    CallCleanup,
    CallCleanupRecovery,
    CallCleanupReconciler,
    CallCleanupSupervisor
  }

  @tracker_timeout 1_000

  def request(actor, tenant, id, options \\ []) do
    with {:ok, call} <- Calls.request_call_hangup(actor, tenant, id, options) do
      continue(call, options)
    end
  rescue
    _error -> {:error, :call_hangup_unavailable}
  catch
    _kind, _reason -> {:error, :call_hangup_unavailable}
  end

  defp continue(%PreparedCall{state: :ended} = call, _options), do: result(call, "ended")

  defp continue(call, options) do
    CallCleanupReconciler.wake(Keyword.get(options, :cleanup_reconciler, CallCleanupReconciler))
    recover(call, options)
  end

  defp recover(
         %PreparedCall{
           incarnation_binding_verified: true,
           hangup_requested_at: %DateTime{},
           incarnation_id: incarnation
         } = call,
         options
       )
       when is_binary(incarnation) and byte_size(incarnation) > 0 do
    row =
      call
      |> Map.take([
        :tenant_key,
        :room_id,
        :incarnation_id,
        :incarnation_binding_verified,
        :hangup_requested_at,
        :gateway_cleanup_required,
        :gateway_cleanup_completed_at
      ])
      |> Map.put(:call_id, call.id)

    recovery = CallCleanupRecovery.reconcile(row, options)

    cond do
      recovery == :replayed -> refreshed(call, options, true)
      call.gateway_cleanup_required -> tracked(call, row, recovery, options)
      true -> refreshed(call, options, false)
    end
  end

  defp recover(_call, _options), do: {:error, :call_hangup_unknown}

  defp tracked(call, row, recovery, options) do
    binding = Map.take(row, [:tenant_key, :call_id, :room_id, :incarnation_id])

    case CallCleanupSupervisor.lookup(binding, @tracker_timeout) do
      {:ok, tracker} ->
        case CallCleanup.snapshot(tracker, @tracker_timeout) do
          %{binding: ^binding, uncertain?: false, engine_outcome: engine}
          when recovery == :requested or engine == :complete ->
            result(call, "ending")

          _unknown ->
            {:error, :call_hangup_unknown}
        end

      _missing ->
        refreshed(call, options, false)
    end
  catch
    :exit, _reason -> refreshed(call, options, false)
  end

  defp refreshed(call, options, completion_proven?) do
    case Calls.fetch_call(call.tenant_key, call.id, options) do
      {:ok, %PreparedCall{tenant_key: tenant, id: id, state: :ended} = stored}
      when tenant == call.tenant_key and id == call.id ->
        result(stored, "ended")

      {:ok,
       %PreparedCall{tenant_key: tenant, id: id, gateway_cleanup_completed_at: %DateTime{}} =
           stored}
      when completion_proven? and tenant == call.tenant_key and id == call.id ->
        result(stored, "ending")

      _unknown ->
        {:error, :call_hangup_unknown}
    end
  end

  defp result(call, status), do: {:ok, %{call_id: call.id, status: status}}
end
