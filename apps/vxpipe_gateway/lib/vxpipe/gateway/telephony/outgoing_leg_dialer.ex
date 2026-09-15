defmodule Vxpipe.Gateway.Telephony.OutgoingLegDialer do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, OutboundLegRequest, Submission}

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    LegUsage,
    MediaAdmission,
    ProviderEndpoint
  }

  @spec dial(
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          GenServer.server(),
          pid(),
          keyword()
        ) :: {:ok, Submission.t(), LegUsage.t() | nil} | {:error, term(), LegUsage.t() | nil}
  def dial(leg_id, request, service, media_admission, leg, usage_options)
      when is_binary(leg_id) and is_pid(leg) and is_list(usage_options) do
    with :ok <- validate(leg_id, request, service),
         {:ok, token} <-
           MediaAdmission.reserve(
             media_admission,
             service.identity.ingress_key,
             leg,
             service.media_token_ttl_ms,
             service
           ),
         dial <- dial_request(leg_id, request, service, token) do
      usage = LegUsage.start_outgoing(request, service, leg_id, usage_options)
      submit(service, media_admission, leg, dial, usage)
    else
      {:error, _reason} = error ->
        :ok = MediaAdmission.revoke(media_admission, leg)
        append_usage(error, nil)
    end
  end

  defp submit(service, media_admission, leg, dial, usage) do
    case Adapter.dial(service.adapter, service.adapter_options, dial) do
      {:ok, submission} ->
        {:ok, submission, LegUsage.identify(usage, submission)}

      {:error, reason} ->
        :ok = MediaAdmission.revoke(media_admission, leg)
        {:error, reason, usage}
    end
  end

  defp append_usage({:error, reason}, usage), do: {:error, reason, usage}

  defp validate(leg_id, %OutboundLegRequest{} = request, %ConfiguredService{} = service) do
    identity = service.identity

    if valid_leg_id?(leg_id) and OutboundLegRequest.valid?(request) and
         identity.provider in [:telnyx, :twilio] and
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
      callback_url: ProviderEndpoint.event_url(service, leg_id),
      media_url: ProviderEndpoint.media_url(service, token),
      answering_machine_detection: service.answering_machine_detection
    }
  end
end
