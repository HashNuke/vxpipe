defmodule Vxpipe.Calls.Test.MCPCatalogRefreshFixture do
  @moduledoc false

  def enqueue_due({owner, _saved}, policy) do
    send(owner, {:catalog_sweep, policy})
    {:ok, 2}
  end

  def fetch_due({owner, saved}, args, policy) do
    send(owner, {:catalog_candidate, args, policy})
    if saved, do: {:ok, saved.connection}, else: {:ok, :obsolete}
  end

  def resolve({owner, saved}, tenant, id) do
    send(owner, {:catalog_credentials, tenant, id})
    {:ok, saved}
  end

  def run(tenant, configuration, options) do
    send(
      Keyword.fetch!(options, :owner),
      {:catalog_protocol, tenant, configuration.secrets, Keyword.fetch!(options, :timeout)}
    )

    {:ok, %{server_name: "Protocol catalog", catalog: []}}
  end

  def refresh_catalog({owner, saved}, tenant, id, generation, guard, attributes) do
    send(owner, {:catalog_publish, tenant, id, generation, guard, attributes})
    {:ok, Map.merge(saved.connection, attributes)}
  end
end
