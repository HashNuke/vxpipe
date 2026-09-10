defmodule Vxpipe.AgentRuntime.Executor do
  @moduledoc "The private submit-only tool boundary implemented by a runtime host."

  @type submission_error :: :rejected | :saturated | :unavailable

  @callback submit(
              binding :: term(),
              arguments :: map(),
              context :: map(),
              invocation_id :: String.t()
            ) :: :accepted | {:error, submission_error()}
end
