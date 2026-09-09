defmodule Vxpipe.MCP.ScriptedProtocolClient do
  @moduledoc false

  @behaviour Vxpipe.MCP.ProtocolClient

  @impl true
  def list_tools(client, cursor, timeout) do
    Agent.get_and_update(client, fn state ->
      case state.responses do
        [response | responses] ->
          call = %{cursor: cursor, timeout: timeout}
          {response, %{state | calls: state.calls ++ [call], responses: responses}}

        [] ->
          {{:error, :unexpected_request}, state}
      end
    end)
  end

  @impl true
  def call_tool(client, name, arguments, timeout) do
    Agent.get_and_update(client, fn state ->
      case state.invocation_responses do
        [response | invocation_responses] ->
          invocation = %{name: name, arguments: arguments, timeout: timeout}

          {response,
           %{
             state
             | invocations: state.invocations ++ [invocation],
               invocation_responses: invocation_responses
           }}

        [] ->
          {{:error, :not_submitted}, state}
      end
    end)
  end
end
