defmodule Vxpipe.Gateway.Telephony.OutgoingLegDialer do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, OutboundLegRequest, Submission}

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    MediaAdmission
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint

  @spec dial(
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          GenServer.server(),
          pid()
        ) :: {:ok, Submission.t()} | {:error, term()}
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
         {:ok, submission} <- Adapter.dial(service.adapter, service.adapter_options, dial) do
      {:ok, submission}
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
end
