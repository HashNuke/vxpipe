defmodule Vxpipe.Gateway.Telephony.OutgoingLegDialer do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, OutboundLegRequest, Submission}

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    MediaAdmission,
    MediaBinding
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint

  @spec dial(
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          GenServer.server(),
          pid()
        ) :: {:ok, :accepted | :unknown} | {:error, term()}
  def dial(leg_id, request, service, media_admission, leg)
      when is_binary(leg_id) and is_pid(leg) do
    with :ok <- validate(leg_id, request, service),
         {:ok, token} <-
           MediaAdmission.reserve(
             media_admission,
             service.identity.ingress_key,
             leg,
             service.media_token_ttl_ms
           ),
         dial <- dial_request(leg_id, request, service, token),
         {:ok, submission} <- Adapter.dial(service.adapter, service.adapter_options, dial),
         {:ok, status} <-
           bind_submission(submission, leg_id, request, service, media_admission, leg) do
      {:ok, status}
    else
      {:error, _reason} = error ->
        :ok = MediaAdmission.revoke(media_admission, leg)
        error
    end
  end

  defp validate(leg_id, %OutboundLegRequest{} = request, %ConfiguredService{} = service) do
    identity = service.identity

    if valid_leg_id?(leg_id) and OutboundLegRequest.valid?(request) and
         identity.provider == :telnyx and
         identity.service_id == request.service_id and
         matching_scope?(identity.scope, request.tenant_id) and
         is_binary(service.outbound_number) do
      :ok
    else
      {:error, :invalid_outbound_telephony_request}
    end
  end

  defp matching_scope?(:application, _tenant_id), do: true
  defp matching_scope?({:tenant, tenant_id}, tenant_id), do: true
  defp matching_scope?(_scope, _tenant_id), do: false

  defp valid_leg_id?(leg_id),
    do: is_binary(leg_id) and byte_size(leg_id) > 0 and byte_size(leg_id) <= 128

  defp dial_request(leg_id, request, service, token) do
    %Dial{
      leg_id: leg_id,
      from: service.outbound_number,
      to: request.to,
      callback_url: PublicEndpoint.event_url(service),
      media_url: PublicEndpoint.media_url(service, token),
      answering_machine_detection: request.answering_machine_detection
    }
  end

  defp bind_submission(
         %Submission{status: :unknown},
         _leg_id,
         _request,
         _service,
         _admission,
         _leg
       ),
       do: {:ok, :unknown}

  defp bind_submission(
         %Submission{
           status: :accepted,
           provider_call_control_id: call_control_id,
           provider_call_leg_id: call_leg_id,
           provider_call_session_id: call_session_id
         },
         leg_id,
         request,
         service,
         media_admission,
         leg
       )
       when is_binary(call_control_id) and is_binary(call_leg_id) and is_binary(call_session_id) do
    binding = %MediaBinding{
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

    case MediaAdmission.bind(media_admission, binding) do
      :ok -> {:ok, :accepted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bind_submission(
         %Submission{status: :accepted},
         _leg_id,
         _request,
         _service,
         _media_admission,
         _leg
       ),
       do: {:error, :incomplete_provider_identity}
end
