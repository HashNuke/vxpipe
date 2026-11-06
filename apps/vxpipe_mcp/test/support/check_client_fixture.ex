defmodule Vxpipe.MCP.CheckClientFixture do
  @moduledoc false
  use GenServer

  def start_link(options) do
    {name, options} = Keyword.split(options, [:name])
    GenServer.start_link(__MODULE__, options, name)
  end

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :test_owner)
    send(owner, {:check_initializing, self()})

    case Keyword.get(options, :test_init) do
      :hold ->
        receive do
          :release -> {:ok, options}
        end

      :fail ->
        {:stop, {:fixture_start_failed, options}}

      _ ->
        {:ok, options}
    end
  end

  @impl true
  def handle_call(request, _from, options) when request in [:get_status, :status] do
    status = %{
      connection_status: :ready,
      protocol_version: "2025-11-25",
      server_info: %{"name" => "Boundary fixture"},
      test_owner: Keyword.fetch!(options, :test_owner),
      test_result: Keyword.get(options, :test_result, {:ok, %{"tools" => []}})
    }

    {:reply, {:ok, status}, options}
  end

  def handle_call(:disconnect, _from, options) do
    send(Keyword.fetch!(options, :test_owner), {:check_disconnected, self()})
    {:reply, :ok, options}
  end

  @impl true
  def handle_info(:crash, options), do: raise("fixture crash: #{inspect(options)}")
end
