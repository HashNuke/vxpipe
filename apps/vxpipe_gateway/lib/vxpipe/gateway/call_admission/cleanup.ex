defmodule Vxpipe.Gateway.CallAdmission.Cleanup do
  @moduledoc false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.PreparedCall
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor}

  def bind(subject, incarnation, options) do
    if Keyword.get(options, :managed_cleanup, false) == true do
      with {:ok, decision, reservation, bound} <-
             Calls.bind_managed_call_admission(subject, incarnation, options),
           :ok <- track(call(bound), reservation, options) do
        {:ok, decision, bound}
      end
    else
      Calls.bind_call_admission(subject, incarnation, options)
    end
  end

  def binding_for(call) do
    %{
      tenant_key: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: call.incarnation_id
    }
  end

  def check_running(%{gateway_cleanup_required: false}), do: :ok
  def check_running(call), do: existing(call)

  def session_binding(%{gateway_cleanup_required: false}), do: {:ok, nil}

  def session_binding(
        %{gateway_cleanup_required: true, incarnation_binding_verified: true} = call
      ),
      do: {:ok, binding_for(call)}

  def session_binding(_unverified), do: {:error, :cleanup_unavailable}

  def existing(call) do
    with {:ok, tracker} <- CallCleanupSupervisor.lookup(binding_for(call)),
         %{sealed?: false, status: :open, uncertain?: false} <- CallCleanup.snapshot(tracker) do
      :ok
    else
      _unavailable -> {:error, :cleanup_unavailable}
    end
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end

  defp track(call, :existing, _options), do: existing(call)

  defp track(call, :new, options) do
    completion =
      options |> Keyword.get(:cleanup_options, []) |> Keyword.put(:calls_options, options)

    case CallCleanupSupervisor.start_new(binding_for(call), nil, completion: completion) do
      {:ok, _tracker} -> :ok
      _unavailable -> {:error, :cleanup_unavailable}
    end
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end

  defp call(%PreparedCall{} = call), do: call
  defp call(subject), do: subject.call
end
