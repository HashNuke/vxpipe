defmodule Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient do
  @moduledoc false

  @behaviour Vxpipe.MCP.ProtocolClient

  @impl true
  def list_tools(client, cursor, timeout) do
    Agent.get_and_update(client, fn state ->
      case state.discovery_responses do
        [response | responses] ->
          call = %{cursor: cursor, timeout: timeout}

          {response,
           %{
             state
             | discovery_calls: state.discovery_calls ++ [call],
               discovery_responses: responses
           }}

        [] ->
          {{:error, :unexpected_discovery}, state}
      end
    end)
  end

  @impl true
  def call_tool(_client, _name, _arguments, _timeout), do: {:error, :not_submitted}
end
