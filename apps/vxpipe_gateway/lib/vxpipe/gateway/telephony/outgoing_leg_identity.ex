defmodule Vxpipe.Gateway.Telephony.OutgoingLegIdentity do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest, Submission}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, MediaBinding}

  @spec from_submission(
          Submission.t(),
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          pid()
        ) :: {:ok, MediaBinding.t()} | {:error, :incomplete_provider_identity}
  def from_submission(
        %Submission{
          status: :accepted,
          provider_call_control_id: call_control_id,
          provider_call_leg_id: call_leg_id,
          provider_call_session_id: call_session_id
        },
        leg_id,
        request,
        service,
        leg
      ) do
    if Enum.all?([call_control_id, call_leg_id], &present?/1) and
         optional_identifier?(call_session_id) do
      {:ok, binding(leg_id, request, service, leg, call_control_id, call_leg_id, call_session_id)}
    else
      {:error, :incomplete_provider_identity}
    end
  end

  @spec from_event(
          Event.t(),
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          pid()
        ) :: {:ok, MediaBinding.t()} | {:error, :telephony_leg_mismatch}
  def from_event(
        %Event{kind: kind} = event,
        leg_id,
        %OutboundLegRequest{} = request,
        %ConfiguredService{} = service,
        leg
      )
      when kind in [:outgoing, :answered, :ended] and is_pid(leg) do
    if Event.valid?(event) and event.leg_id == leg_id and
         event.provider == service.identity.provider and
         event.provider_connection_id == service.identity.provider_connection_id and
         optional_identifier?(event.provider_call_session_id) and
         event.from == service.outbound_number and event.to == request.to do
      {:ok,
       binding(
         leg_id,
         request,
         service,
         leg,
         event.provider_call_control_id,
         event.provider_call_leg_id,
         event.provider_call_session_id
       )}
    else
      {:error, :telephony_leg_mismatch}
    end
  end

  defp binding(leg_id, request, service, leg, call_control_id, call_leg_id, call_session_id) do
    %MediaBinding{
      provider: service.identity.provider,
      service_id: service.identity.service_id,
      ingress_key: service.identity.ingress_key,
      tenant_id: request.tenant_id,
      call_id: request.call_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.participant_id,
      provider_connection_id: service.identity.provider_connection_id,
      provider_call_control_id: call_control_id,
      provider_call_leg_id: call_leg_id,
      provider_call_session_id: call_session_id,
      client_state_leg_id: leg_id,
      leg: leg
    }
  end

  defp present?(value), do: is_binary(value) and value != ""
  defp optional_identifier?(nil), do: true
  defp optional_identifier?(value), do: present?(value)
end
