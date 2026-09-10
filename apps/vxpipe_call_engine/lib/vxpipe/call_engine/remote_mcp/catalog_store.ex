defmodule Vxpipe.CallEngine.RemoteMCP.CatalogStore do
  @moduledoc """
  Owns the current immutable MCP integration-catalog snapshot.

  Remote discovery happens before publication so catalog readers never wait on network work.
  """

  use GenServer

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog

  @call_timeout_ms 5_000

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @spec snapshot(GenServer.server()) :: {:ok, IntegrationCatalog.t()}
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot, @call_timeout_ms)
  end

  @spec publish(GenServer.server(), IntegrationCatalog.t()) :: :ok
  def publish(server \\ __MODULE__, catalog)

  def publish(server, %IntegrationCatalog{} = catalog) do
    GenServer.call(server, {:publish, catalog}, @call_timeout_ms)
  end

  @impl true
  def init(options) do
    with {:ok, options} <- Keyword.validate(options, [:catalog, :name]),
         {:ok, catalog} <- initial_catalog(Keyword.get(options, :catalog)) do
      {:ok, catalog}
    else
      _invalid -> {:stop, :invalid_catalog_store_configuration}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, %IntegrationCatalog{} = catalog) do
    {:reply, {:ok, catalog}, catalog}
  end

  def handle_call({:publish, %IntegrationCatalog{} = replacement}, _from, _catalog) do
    {:reply, :ok, replacement}
  end

  defp initial_catalog(nil), do: IntegrationCatalog.new(application: %{}, tenants: %{})
  defp initial_catalog(%IntegrationCatalog{} = catalog), do: {:ok, catalog}
  defp initial_catalog(_catalog), do: {:error, :invalid_catalog}
end
