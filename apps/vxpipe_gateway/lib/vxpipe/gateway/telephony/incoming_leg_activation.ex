defmodule Vxpipe.Gateway.Telephony.IncomingLegActivation do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Answer, LegReference}
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.Id

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    MediaAdmission,
    MediaBinding
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint

  @spec activate(ConfiguredService.t(), TelephonyAdmissionClaim.t(), String.t(), pid(), keyword()) ::
          {:ok, MediaBinding.t(), Vxpipe.CallEngine.Telephony.Submission.t()} | {:error, term()}
  def activate(
        %ConfiguredService{} = service,
        %TelephonyAdmissionClaim{} = claim,
        incarnation_id,
        leg,
        options \\ []
      )
      when is_binary(incarnation_id) and is_pid(leg) do
    media_admission = Keyword.get(options, :media_admission, MediaAdmission)
    leg_id = Keyword.get(options, :leg_id, fn -> Id.generate(:telephony_leg) end)

    with :ok <- matching_service(service, claim),
         {:ok, client_state_leg_id} <- generate_leg_id(leg_id),
         binding <- binding(service, claim, incarnation_id, client_state_leg_id, leg),
         {:ok, token} <-
           MediaAdmission.issue(media_admission, binding, service.media_token_ttl_ms),
         request <- answer_request(service, binding, token),
         {:ok, submission} <- Adapter.answer(service.adapter, service.adapter_options, request) do
      {:ok, binding, submission}
    else
      {:error, reason} = error ->
        :ok = MediaAdmission.revoke(media_admission, leg)
        if is_atom(reason) or is_tuple(reason), do: error, else: {:error, :activation_failed}
    end
  end

  defp matching_service(service, claim) do
    identity = service.identity

    if identity.provider == claim.provider and
         identity.service_id == claim.service and
         identity.provider_connection_id == claim.provider_connection_id and
         matching_scope?(identity.scope, claim.call.tenant_key) do
      :ok
    else
      {:error, :telephony_service_mismatch}
    end
  end

  defp matching_scope?(:application, _tenant_id), do: true
  defp matching_scope?({:tenant, tenant_id}, tenant_id), do: true
  defp matching_scope?(_scope, _tenant_id), do: false

  defp generate_leg_id(generator) when is_function(generator, 0) do
    case generator.() do
      value when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 128 ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_telephony_leg_id}
    end
  end

  defp generate_leg_id(_invalid), do: {:error, :invalid_telephony_leg_id}

  defp binding(service, claim, incarnation_id, client_state_leg_id, leg) do
    %MediaBinding{
      provider: claim.provider,
      service_id: service.identity.service_id,
      ingress_key: service.identity.ingress_key,
      tenant_id: claim.call.tenant_key,
      call_id: claim.call.id,
      room_id: claim.call.room_id,
      incarnation_id: incarnation_id,
      participant_id: claim.participant_id,
      provider_connection_id: claim.provider_connection_id,
      provider_call_control_id: claim.provider_call_control_id,
      provider_call_leg_id: claim.provider_call_leg_id,
      provider_call_session_id: claim.provider_call_session_id,
      client_state_leg_id: client_state_leg_id,
      leg: leg
    }
  end

  defp answer_request(service, binding, token) do
    %Answer{
      leg: %LegReference{
        leg_id: binding.client_state_leg_id,
        provider_call_control_id: binding.provider_call_control_id
      },
      media_url: PublicEndpoint.media_url(service, token)
    }
  end
end
