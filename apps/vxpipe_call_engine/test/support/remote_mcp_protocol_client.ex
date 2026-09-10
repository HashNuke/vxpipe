defmodule Vxpipe.CallEngine.TestRemoteMCPProtocolClient do
  @moduledoc false

  @behaviour Vxpipe.MCP.ProtocolClient

  @impl true
  def list_tools(_client, _cursor, _timeout), do: {:error, :unexpected_discovery}

  @impl true
  def call_tool(client, name, arguments, timeout) do
    client
    |> Agent.get_and_update(fn state ->
      case state.responses do
        [response | responses] ->
          invocation = %{name: name, arguments: arguments, timeout: timeout}

          {response,
           %{state | invocations: state.invocations ++ [invocation], responses: responses}}

        [] ->
          {{:error, :not_submitted}, state}
      end
    end)
    |> await()
  end

  defp await({:wait, observer, response}) do
    send(observer, {:test_remote_mcp_invocation_started, self()})

    receive do
      :release_test_remote_mcp -> response
    end
  end

  defp await(response), do: response
end
