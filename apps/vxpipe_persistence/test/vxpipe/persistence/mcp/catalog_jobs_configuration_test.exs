defmodule Vxpipe.Persistence.MCP.CatalogJobsConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Persistence.MCP.{CatalogRefreshWorker, CatalogSweepWorker}

  test "configured maintenance uses the existing Repo and bounded periodic queues" do
    assert {:ok, settings} = Application.fetch_env(:vxpipe_persistence, Oban)
    assert Keyword.fetch!(settings, :repo) == Vxpipe.Persistence.Repo
    assert Keyword.fetch!(settings, :name) == Vxpipe.Persistence.Jobs
    assert Keyword.fetch!(settings, :queues) == [maintenance: 1, mcp_catalog: 4]
    assert Keyword.fetch!(settings, :cron) == [crontab: [{"* * * * *", CatalogSweepWorker}]]
    assert Keyword.fetch!(settings, :lifeline) == [rescue_after: {5, :minutes}]
    assert Keyword.fetch!(settings, :pruner) == [max_age: {7, :days}]
    assert {:ok, policy} = Application.fetch_env(:vxpipe_calls, :mcp_catalog_refresh)
    assert Keyword.fetch!(policy, :expiry_seconds) == 3_600
    assert Keyword.fetch!(policy, :reschedule_after_seconds) == 1_800
  end

  test "invalid timeout configuration cannot disable the worker lifetime bound" do
    previous = Application.fetch_env(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms)

    on_exit(fn ->
      case previous do
        {:ok, value} ->
          Application.put_env(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms, value)

        :error ->
          Application.delete_env(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms)
      end
    end)

    for value <- [0, -1, :infinity, 300_000],
        worker <- [CatalogRefreshWorker, CatalogSweepWorker] do
      Application.put_env(:vxpipe_persistence, :mcp_catalog_worker_timeout_ms, value)
      assert_raise ArgumentError, fn -> worker.timeout(%Oban.Job{}) end
    end
  end
end
