defmodule Vxpipe.CallEngine.TestRemoteMCPClient do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.MCP.ClientRuntime

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.fetch!(options, :test_client),
      name: Keyword.fetch!(options, :name)
    )
  end

  @impl Vxpipe.MCP.ClientRuntime
  def status(client), do: GenServer.call(client, :status)

  @impl GenServer
  def init(client), do: {:ok, {client, Process.monitor(client)}}

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply, {:ok, %{connection_status: :ready, protocol_version: "2025-11-25"}}, state}
  end

  def handle_call({:get_and_update, function}, _from, {client, _reference} = state) do
    {:reply, Agent.get_and_update(client, function), state}
  end

  @impl GenServer
  def handle_info({:DOWN, reference, :process, client, _reason}, {client, reference}) do
    {:stop, :normal, {client, reference}}
  end
end
