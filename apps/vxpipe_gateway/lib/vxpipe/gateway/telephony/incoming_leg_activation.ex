defmodule Vxpipe.Gateway.Telephony.IncomingLegActivation do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Answer, LegReference}
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.Id

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    IncomingLegActivationContext,
    IncomingLegActivationResult,
    LegUsage,
    MediaAdmission,
    MediaBinding,
    ProviderEndpoint
  }

  @spec activate(ConfiguredService.t(), TelephonyAdmissionClaim.t(), String.t(), pid(), keyword()) ::
          {:ok, IncomingLegActivationResult.t()} | {:error, term()}
  def activate(
        %ConfiguredService{} = service,
        %TelephonyAdmissionClaim{} = claim,
        incarnation_id,
        leg,
        options \\ []
      )
      when is_binary(incarnation_id) and is_pid(leg) do
    with {:ok, prepared} <- prepare(service, claim, incarnation_id, leg, options) do
      case submit(prepared) do
        {:ok, result} -> {:ok, result}
        {:error, reason, _retained} -> {:error, reason}
      end
    end
  end

  @doc "Prepares media admission and usage without submitting an answer to the carrier."
  @spec prepare(ConfiguredService.t(), TelephonyAdmissionClaim.t(), String.t(), pid(), keyword()) ::
          {:ok, IncomingLegActivationContext.t()} | {:error, term()}
  def prepare(service, claim, incarnation_id, leg, options \\ [])

  def prepare(
        %ConfiguredService{} = service,
        %TelephonyAdmissionClaim{} = claim,
        incarnation_id,
        leg,
        options
      )
      when is_binary(incarnation_id) and is_pid(leg) do
    media_admission = Keyword.get(options, :media_admission, MediaAdmission)
    leg_id = Keyword.get(options, :leg_id, fn -> Id.generate(:telephony_leg) end)

    with :ok <- matching_service(service, claim),
         {:ok, client_state_leg_id} <- generate_leg_id(leg_id),
         binding <- binding(service, claim, incarnation_id, client_state_leg_id, leg),
         {:ok, token} <-
           MediaAdmission.issue(media_admission, binding, service.media_token_ttl_ms, service),
         media_url <- ProviderEndpoint.media_url(service, token),
         request <- answer_request(binding, media_url) do
      usage = LegUsage.start_incoming(binding, options)

      {:ok,
       %IncomingLegActivationContext{
         binding: binding,
         service: service,
         media_admission: media_admission,
         media_url: media_url,
         request: request,
         usage: usage
       }}
    else
      {:error, reason} = error ->
        :ok = MediaAdmission.revoke(media_admission, leg)
        if is_atom(reason) or is_tuple(reason), do: error, else: {:error, :activation_failed}
    end
  end

  @doc """
  Submits a prepared answer. The owner retains the prepared context while this call
  is in flight. Rejection returns that context with finalized usage; an accepted or
  unknown submission returns the existing activation result without discarding the
  original carrier binding.
  """
  @spec submit(IncomingLegActivationContext.t()) ::
          {:ok, IncomingLegActivationResult.t()}
          | {:error, term(), IncomingLegActivationContext.t()}
  def submit(%IncomingLegActivationContext{} = prepared) do
    service = prepared.service

    case Adapter.answer(service.adapter, service.adapter_options, prepared.request) do
      {:ok, submission} ->
        {:ok,
         %IncomingLegActivationResult{
           binding: prepared.binding,
           media_url: prepared.media_url,
           submission: submission,
           service: service,
           usage: LegUsage.identify(prepared.usage, submission)
         }}

      {:error, reason} ->
        retained = %{prepared | usage: LegUsage.fail(prepared.usage, :failed)}
        :ok = MediaAdmission.revoke(prepared.media_admission, prepared.binding.leg)
        reason = if is_atom(reason) or is_tuple(reason), do: reason, else: :activation_failed
        {:error, reason, retained}
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

  defp answer_request(binding, media_url) do
    %Answer{
      leg: %LegReference{
        leg_id: binding.client_state_leg_id,
        provider_call_control_id: binding.provider_call_control_id
      },
      media_url: media_url
    }
  end
end
