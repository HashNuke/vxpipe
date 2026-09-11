defmodule Vxpipe.CallEngine.Usage.EffectiveAmount do
  @moduledoc "A derived effective quantity for one usage attempt and measured component."

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}

  @enforce_keys [
    :attempt_id,
    :capability,
    :provider,
    :attribution,
    :component,
    :unit,
    :quantity,
    :mode,
    :status,
    :provenance,
    :observation_ids
  ]

  defstruct @enforce_keys ++ [included_in: nil]

  @type t :: %__MODULE__{
          attempt_id: String.t(),
          capability: Observation.capability(),
          provider: ProviderContext.t(),
          attribution: Attribution.t(),
          component: String.t(),
          unit: Measurement.unit(),
          quantity: Measurement.quantity(),
          mode: Measurement.mode(),
          status: Measurement.status(),
          provenance: Measurement.provenance(),
          included_in: String.t() | nil,
          observation_ids: [String.t()]
        }
end
