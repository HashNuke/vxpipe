defmodule Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient do
  @moduledoc false

  @behaviour Vxpipe.MCP.ProtocolClient

  @impl true
  def list_tools(client, cursor, timeout) do
    response =
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

    case response do
      {:wait, observer, result} ->
        send(observer, {:test_catalog_discovery_waiting, self(), client})
        receive do: (:release_catalog_discovery -> result)

      result ->
        result
    end
  end

  @impl true
  def call_tool(_client, _name, _arguments, _timeout), do: {:error, :not_submitted}
end
