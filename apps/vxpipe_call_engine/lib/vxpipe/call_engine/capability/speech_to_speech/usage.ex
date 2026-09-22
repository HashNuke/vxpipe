defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Usage do
  @moduledoc """
  Per-turn usage observations for one agent-owned STS allocation.

  Each settled STS turn produces exactly one `:speech_to_speech` observation
  carrying the locally measured egress duration, plus one
  `:output_speech_to_text` observation when the agent-output STT leg is
  selected. Only locally measured quantities are reported; provider-reported
  token counts are never inferred from audio bytes.
  """

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}

  @type context :: %{
          required(:tenant_id) => String.t(),
          required(:call_id) => String.t(),
          required(:room_id) => String.t(),
          required(:incarnation_id) => String.t(),
          required(:participant_id) => String.t(),
          optional(:activation_id) => String.t() | nil,
          optional(:provider) => ProviderContext.t()
        }

  @spec turn_observations(
          map(),
          map(),
          reference(),
          atom(),
          non_neg_integer(),
          non_neg_integer(),
          boolean()
        ) ::
          [Observation.t()]
  def turn_observations(
        context,
        descriptor,
        provider_turn,
        outcome,
        egress_ms,
        stt_ms,
        output_stt?
      )
      when is_map(context) and is_reference(provider_turn) and is_integer(egress_ms) and
             egress_ms >= 0 and is_integer(stt_ms) and stt_ms >= 0 and is_boolean(output_stt?) do
    with {:ok, provider} <- provider_context(context, descriptor),
         {:ok, attribution} <- attribution(context),
         {:ok, measurement} <- egress_measurement(egress_ms),
         {:ok, observation} <-
           Observation.new(
             id: Id.generate(:turn),
             tenant_id: context.tenant_id,
             call_id: context.call_id,
             attempt_id: inspect(provider_turn),
             capability: :speech_to_speech,
             provider: provider,
             attribution: attribution,
             measurement: measurement,
             outcome: outcome,
             observed_at: DateTime.utc_now(:millisecond)
           ) do
      if output_stt? do
        [
          observation
          | output_stt_observation(context, provider, attribution, provider_turn, outcome, stt_ms)
        ]
      else
        [observation]
      end
    else
      _invalid -> []
    end
  end

  defp output_stt_observation(context, provider, attribution, provider_turn, outcome, stt_ms) do
    with {:ok, measurement} <- recognition_measurement(stt_ms),
         {:ok, observation} <-
           Observation.new(
             id: Id.generate(:turn),
             tenant_id: context.tenant_id,
             call_id: context.call_id,
             attempt_id: inspect(provider_turn) <> ":output-stt",
             capability: :output_speech_to_text,
             provider: provider,
             attribution: attribution,
             measurement: measurement,
             outcome: outcome,
             observed_at: DateTime.utc_now(:millisecond)
           ) do
      [observation]
    else
      _invalid -> []
    end
  end

  defp provider_context(%{provider: %ProviderContext{} = provider}, _descriptor),
    do: {:ok, provider}

  defp provider_context(_context, %{usage_identity: %{provider: provider, model: model}}) do
    ProviderContext.new(name: to_string(provider), model: to_string(model))
  end

  defp provider_context(_context, _descriptor), do: :error

  defp attribution(context) do
    Attribution.new(
      room_id: Map.get(context, :room_id),
      incarnation_id: Map.get(context, :incarnation_id),
      participant_id: Map.get(context, :participant_id),
      activation_id: Map.get(context, :activation_id)
    )
  end

  defp egress_measurement(ms) do
    Measurement.new(
      component: "egress_audio",
      unit: :milliseconds,
      quantity: ms,
      mode: :delta,
      status: :final,
      provenance: :locally_measured
    )
  end

  defp recognition_measurement(ms) do
    Measurement.new(
      component: "output_recognition",
      unit: :milliseconds,
      quantity: ms,
      mode: :delta,
      status: :final,
      provenance: :locally_measured
    )
  end
end
