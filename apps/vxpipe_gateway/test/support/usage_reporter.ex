defmodule Vxpipe.Gateway.TestUsageReporter do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Telephony.UsageReporter

  @impl true
  def report(observer, observations) do
    send(observer, {:test_usage_observations, observations})
    :ok
  end
end
