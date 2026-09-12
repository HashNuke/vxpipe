defmodule Vxpipe.Gateway.Telephony.CallEngineUsageReporter do
  @moduledoc false

  @behaviour Vxpipe.Gateway.Telephony.UsageReporter

  alias Vxpipe.CallEngine

  @impl true
  def report(_context, observations), do: CallEngine.record_telephony_usage(observations)
end
