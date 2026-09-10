defmodule Vxpipe.CallEngine.AgentRuntime.InvocationExecutor do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.Executor

  alias Vxpipe.CallEngine.AgentRuntime.Correlation
  alias Vxpipe.CallEngine.Tool.{InvocationBinding, InvocationRegistry}

  @impl true
  def submit(
        %InvocationBinding{} = binding,
        arguments,
        %Correlation{} = correlation,
        invocation_id
      ) do
    InvocationRegistry.submit(
      correlation.invocation_registry,
      binding,
      arguments,
      correlation.tool_context,
      invocation_id
    )
  end

  def submit(_binding, _arguments, _correlation, _invocation_id), do: {:error, :rejected}
end
