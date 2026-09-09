defmodule Vxpipe.MCP.ReadyClient do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    {name_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, name_opts)
  end

  def status(client), do: GenServer.call(client, :status)

  @impl true
  def init(opts) do
    status =
      Keyword.get(opts, :test_status, %{
        connection_status: :ready,
        protocol_version: "2025-11-25"
      })

    {:ok, status}
  end

  @impl true
  def handle_call(:status, _from, status), do: {:reply, {:ok, status}, status}
end
