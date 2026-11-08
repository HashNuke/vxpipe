defmodule Vxpipe.Persistence.MCP.CatalogRefreshWorker do
  @moduledoc "Runs one tenant catalog refresh with bounded retries and a redacted queue outcome."

  use Oban.Worker,
    queue: :mcp_catalog,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, keys: [:tenant, :connection_id, :generation]]

  @impl Oban.Worker
  def timeout(_job) do
    value = Application.get_env(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms, 30_000)

    if is_integer(value) and value in 1..180_000,
      do: value,
      else: raise(ArgumentError, "invalid MCP catalog worker timeout")
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Vxpipe.Calls.MCPCatalogRefresh.refresh(args) do
      :ok -> :ok
      _failure -> {:error, :mcp_catalog_refresh_failed}
    end
  rescue
    _error -> {:error, :mcp_catalog_refresh_failed}
  catch
    _kind, _reason -> {:error, :mcp_catalog_refresh_failed}
  end
end
