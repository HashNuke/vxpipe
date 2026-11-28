defmodule Vxpipe.AgentRuntime.GuardrailFeedback do
  @moduledoc "The private failure message sent to the conversational model."
  @spec encode([%{event: atom(), messages: [String.t()]}]) :: binary()
  def encode(failures),
    do: JSON.encode!(%{type: "guardrail_failure", status: "blocked", failures: failures})
end
