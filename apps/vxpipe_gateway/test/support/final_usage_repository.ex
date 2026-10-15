defmodule Vxpipe.Gateway.TestFinalUsageRepository do
  @moduledoc false

  def store_usage_observation({observer, result}, observation) do
    send(observer, {:stored_carrier_usage, observation})
    result.(observation)
  end
end
