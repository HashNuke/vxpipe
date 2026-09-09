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
end
