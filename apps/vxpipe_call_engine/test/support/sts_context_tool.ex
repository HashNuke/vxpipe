defmodule Vxpipe.CallEngine.STSContextTool do
  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl true
  def definition do
    %Definition{
      name: "echo_context",
      description: "Return public invocation identity for a contract test.",
      parameters: %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
    }
  end

  @impl true
  def execute(arguments, %Context{} = context) when map_size(arguments) == 0 do
    {:ok,
     %{
       "tool_call_id" => context.tool_call_id,
       "command_id" => context.command_id,
       "correlation_id" => context.correlation_id,
       "connection_id" => context.connection_id,
       "agent_id" => context.agent_participant_id
     }}
  end
end
