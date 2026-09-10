defmodule Vxpipe.CallEngine.TestRemoteMCPConfigurationSource do
  @moduledoc false

  use Agent

  @behaviour Vxpipe.CallEngine.RemoteMCP.ConfigurationSource

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        calls: 0,
        observer: Keyword.fetch!(options, :observer),
        response: Keyword.fetch!(options, :response)
      }
    end)
  end

  def put_response(server, response) do
    Agent.update(server, &%{&1 | response: response})
  end

  @impl true
  def fetch(options) do
    server = Keyword.fetch!(options, :server)

    {response, observer, call_number} =
      Agent.get_and_update(server, fn state ->
        call_number = state.calls + 1
        {{state.response, state.observer, call_number}, %{state | calls: call_number}}
      end)

    send(observer, {:test_remote_mcp_configuration_fetch, self(), call_number})
    resolve(response)
  end

  defp resolve({:block, observer}) do
    send(observer, {:test_remote_mcp_configuration_blocked, self()})

    receive do
      {:test_remote_mcp_configuration_release, result} -> result
    end
  end

  defp resolve(response), do: response
end
