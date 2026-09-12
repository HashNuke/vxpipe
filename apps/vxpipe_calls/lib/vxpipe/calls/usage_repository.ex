defmodule Vxpipe.Calls.UsageRepository do
  @moduledoc "Persistence port for immutable usage observations and their effective projections."

  alias Vxpipe.CallEngine.Usage.{EffectiveAmount, Observation}

  @type context :: term()

  @callback store_usage_observation(context(), Observation.t()) ::
              {:ok, Observation.t()} | {:error, term()}

  @callback fetch_usage_amounts(context(), String.t(), String.t()) ::
              {:ok, [EffectiveAmount.t()]} | {:error, term()}

  @callback fetch_usage_observations(context(), String.t(), String.t()) ::
              {:ok, [Observation.t()]} | {:error, term()}
end
