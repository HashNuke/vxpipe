defmodule Vxpipe.CallEngine.Agent do
  @moduledoc false

  use Jido.AI.Agent,
    name: "vxpipe_call_agent",
    description: "A definition-pinned Vxpipe call participant.",
    tools: [],
    system_prompt: false,
    model: :fast,
    max_iterations: 3,
    streaming: true,
    request_policy: :reject,
    tool_max_retries: 0,
    tool_retry_backoff_ms: 0,
    observability: %{
      emit_lifecycle_signals?: false,
      emit_llm_deltas?: true,
      redact_tool_args?: false
    }
end
