defmodule Vxpipe.Gateway.IncomingCallAdmission do
  @moduledoc false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.CallEngine.Telephony.{Adapter, EndLeg, LegReference}
  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions
  alias Vxpipe.Gateway.CallCleanupSupervisor
  alias Vxpipe.Gateway.Telephony.CarrierCleanup
  alias Vxpipe.Gateway.Telephony.IncomingLegActivationResult
  alias Vxpipe.Gateway.Telephony.IncomingLegIdentity

  def start(options, claim, owner, token) do
    runtime = Keyword.put(CallEngineOptions.build(options), :call_admission, {owner, token})

    with {:ok, room} <- CallEngine.start_call(claim.call.plan, runtime) do
      case CallEngine.monitor_room(claim.call.tenant_key, claim.call.room_id, room.incarnation_id) do
        {:ok, monitor} ->
          if Keyword.get(options, :managed_cleanup, false) == true,
            do: {:ok, room, monitor, :managed_cleanup},
            else: {:ok, room, monitor}

        error ->
          CallEngine.cancel_call_admission(
            claim.call.tenant_key,
            claim.call.room_id,
            room.incarnation_id,
            token
          )

          error
      end
    end
  end

  def bind(options, claim, incarnation) do
    if Keyword.get(options, :managed_cleanup, false) == true do
      bind_managed(options, claim, incarnation)
    else
      Calls.bind_call_admission(claim, incarnation, options)
    end
  end

  defp bind_managed(options, claim, incarnation) do
    case Calls.bind_managed_call_admission(claim, incarnation, options) do
      {:ok, decision, reservation, updated} ->
        attach_cleanup(options, updated, decision, reservation)

      {:error, reason} ->
        {:error, reason, claim, nil}
    end
  end

  defp attach_cleanup(options, claim, decision, reservation) do
    binding = %{
      tenant_key: claim.call.tenant_key,
      call_id: claim.call.id,
      room_id: claim.call.room_id,
      incarnation_id: claim.call.incarnation_id
    }

    cleanup_options =
      options
      |> Keyword.get(:cleanup_options, [])
      |> Keyword.put(:calls_options, options)

    started = start_tracker(binding, reservation, cleanup_options)

    case CarrierCleanup.attach(binding, :incoming_leg, binding, cleanup_options) do
      {:ok, cleanup} when started == :ok -> {:ok, decision, claim, cleanup}
      {:ok, cleanup} -> {:error, :cleanup_unavailable, claim, cleanup}
      {:error, reason, cleanup} -> {:error, reason, claim, cleanup}
      {:error, reason} -> {:error, reason, claim, nil}
    end
  rescue
    _invalid_options -> {:error, :cleanup_unavailable, claim, nil}
  catch
    _kind, _reason -> {:error, :cleanup_unavailable, claim, nil}
  end

  defp start_tracker(_binding, :existing, _options), do: :ok

  defp start_tracker(binding, :new, options) do
    case CallCleanupSupervisor.start_new(binding, {:incoming_leg, self()}, completion: options) do
      {:ok, _tracker} -> :ok
      _failure -> {:error, :cleanup_unavailable}
    end
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end

  # The owner applies usage transitions to its current state after the request.
  # Callbacks can connect or finish the retained attempt while HTTP is blocked.
  def submit(prepared) do
    service = prepared.service

    case Adapter.answer(service.adapter, service.adapter_options, prepared.request) do
      {:ok, submission} ->
        {:ok,
         %IncomingLegActivationResult{
           binding: prepared.binding,
           media_url: prepared.media_url,
           submission: submission,
           service: service,
           usage: prepared.usage
         }}

      {:error, reason} ->
        {:error, reason, prepared}
    end
  end

  def release(claim, token) do
    CallEngine.admit_call(
      claim.call.tenant_key,
      claim.call.room_id,
      claim.call.incarnation_id,
      token
    )
  end

  def cancel(claim, token, _reason) do
    CallEngine.cancel_call_admission(
      claim.call.tenant_key,
      claim.call.room_id,
      claim.call.incarnation_id,
      token
    )
  end

  def end_leg(service, event, activation, reason) do
    leg_id =
      case activation do
        %IncomingLegActivationResult{binding: binding} -> binding.client_state_leg_id
        %IncomingLegIdentity{binding: binding} -> binding.client_state_leg_id
        _unprepared -> event.provider_call_leg_id
      end

    Adapter.end_leg(service.adapter, service.adapter_options, %EndLeg{
      leg: %LegReference{leg_id: leg_id, provider_call_control_id: event.provider_call_control_id},
      reason: reason
    })
  end
end
