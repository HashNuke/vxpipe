defmodule Vxpipe.CallEngine.TestRemoteMCPProtocolClient do
  @moduledoc false

  @behaviour Vxpipe.MCP.ProtocolClient

  @impl true
  def list_tools(_client, _cursor, _timeout), do: {:error, :unexpected_discovery}

  @impl true
  def call_tool(client, name, arguments, timeout) do
    Agent.get_and_update(client, fn state ->
      case state.responses do
        [response | responses] ->
          invocation = %{name: name, arguments: arguments, timeout: timeout}

          {response,
           %{state | invocations: state.invocations ++ [invocation], responses: responses}}

        [] ->
          {{:error, :not_submitted}, state}
      end
    end)
  end
end
