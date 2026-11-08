defmodule Vxpipe.Persistence.MCP.CatalogSweepWorker do
  @moduledoc "Schedules a bounded batch of stale tenant catalogs through the Calls workflow."

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def timeout(_job) do
    value = Application.get_env(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms, 30_000)

    if is_integer(value) and value in 1..180_000,
      do: value,
      else: raise(ArgumentError, "invalid MCP catalog worker timeout")
  end

  @impl Oban.Worker
  def perform(_job) do
    case Vxpipe.Calls.MCPCatalogRefresh.sweep() do
      {:ok, count} -> {:ok, count}
      _failure -> {:error, :mcp_catalog_sweep_failed}
    end
  rescue
    _error -> {:error, :mcp_catalog_sweep_failed}
  catch
    _kind, _reason -> {:error, :mcp_catalog_sweep_failed}
  end
end
