defmodule Vxpipe.Gateway.IncomingCallAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Telephony.{Adapter, EndLeg, LegReference}
  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions
  alias Vxpipe.Gateway.Telephony.IncomingLegActivationResult

  def start(options, claim, owner, token) do
    runtime = Keyword.put(CallEngineOptions.build(options), :call_admission, {owner, token})

    with {:ok, room} <- CallEngine.start_call(claim.call.plan, runtime) do
      case CallEngine.monitor_room(claim.call.tenant_key, claim.call.room_id, room.incarnation_id) do
        {:ok, monitor} ->
          {:ok, room, monitor}

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
        _unprepared -> event.provider_call_leg_id
      end

    Adapter.end_leg(service.adapter, service.adapter_options, %EndLeg{
      leg: %LegReference{leg_id: leg_id, provider_call_control_id: event.provider_call_control_id},
      reason: reason
    })
  end
end
