defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.ProviderUsage do
  @moduledoc "Projects provider-reported voice and delegated model usage onto call observations."

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}

  def observations(nil, _descriptor, _usage), do: []

  def observations(context, descriptor, %{kind: :voice, milliseconds: ms}) do
    build(context, descriptor.usage_identity.model, :speech_to_speech, [
      {"voice_audio", :milliseconds, ms}
    ])
  end

  def observations(context, _descriptor, %{
        kind: :backend,
        model: model,
        input_tokens: input,
        output_tokens: output
      }) do
    build(context, model, :model_inference, [
      {"input_tokens", :tokens, input},
      {"output_tokens", :tokens, output}
    ])
  end

  def observations(_context, _descriptor, _usage), do: []

  defp build(context, model, capability, components) do
    with {:ok, provider} <- ProviderContext.new(name: "openai", model: model),
         {:ok, attribution} <-
           Attribution.new(
             room_id: Map.get(context, :room_id),
             incarnation_id: Map.get(context, :incarnation_id),
             participant_id: Map.get(context, :participant_id),
             activation_id: Map.get(context, :activation_id)
           ) do
      attempt_id = Id.generate(:turn)

      Enum.flat_map(components, fn {component, unit, quantity} ->
        with {:ok, measurement} <-
               Measurement.new(
                 component: component,
                 unit: unit,
                 quantity: quantity,
                 mode: :delta,
                 status: :final,
                 provenance: :provider_reported
               ),
             {:ok, observation} <-
               Observation.new(
                 id: Id.generate(:turn),
                 tenant_id: context.tenant_id,
                 call_id: context.call_id,
                 attempt_id: attempt_id,
                 capability: capability,
                 provider: provider,
                 attribution: attribution,
                 measurement: measurement,
                 outcome: :succeeded,
                 observed_at: DateTime.utc_now(:microsecond)
               ) do
          [observation]
        else
          _invalid -> []
        end
      end)
    else
      _invalid -> []
    end
  end
end
