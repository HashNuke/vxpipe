defmodule Vxpipe.Calls.UsageTotal do
  @moduledoc "One non-overlapping operator total at the most specific supported dimensions."

  alias Vxpipe.CallEngine.Usage.{Measurement, Observation}

  @enforce_keys [
    :capability,
    :provider_name,
    :unit,
    :quantity,
    :provenance,
    :amount_count
  ]

  defstruct @enforce_keys ++
              [
                :integration_id,
                :model,
                :voice,
                :participant_id,
                :activation_id,
                :service_interval_id,
                :leg_id,
                :turn_id,
                :utterance_id,
                :tool_call_id
              ]

  @type t :: %__MODULE__{
          capability: Observation.capability(),
          provider_name: String.t(),
          integration_id: String.t() | nil,
          model: String.t() | nil,
          voice: String.t() | nil,
          participant_id: String.t() | nil,
          activation_id: String.t() | nil,
          service_interval_id: String.t() | nil,
          leg_id: String.t() | nil,
          turn_id: String.t() | nil,
          utterance_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          unit: Measurement.unit(),
          quantity: Measurement.quantity(),
          provenance: Measurement.provenance(),
          amount_count: pos_integer()
        }
end
