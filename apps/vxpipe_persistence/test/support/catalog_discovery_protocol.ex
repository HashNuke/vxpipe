defmodule Vxpipe.Persistence.Test.CatalogDiscoveryProtocol do
  @moduledoc false

  def run(tenant, configuration, options) do
    if Vxpipe.Persistence.Repo.in_transaction?(),
      do: raise("catalog network work entered a database transaction")

    owner = Keyword.get(options, :owner)
    if owner, do: send(owner, {:catalog_job_process, self()})

    if marker = Keyword.get(options, :raise_marker), do: raise(marker)

    configuration = %{configuration | endpoint: Keyword.fetch!(options, :endpoint)}
    result = Vxpipe.MCP.ConnectionCheck.run_loopback_test(tenant, configuration, options)

    if Keyword.get(options, :hold_result, false) do
      send(owner, {:catalog_result_held, self()})

      receive do
        :release_catalog_result -> :ok
      after
        5_000 -> raise "catalog result test barrier timed out"
      end
    end

    result
  end

  def job_event(_event, _measurements, metadata, owner),
    do: send(owner, {:catalog_job_exception, metadata.job.id})

  def job_finished(_event, _measurements, metadata, owner),
    do: send(owner, {:catalog_job_finished, self(), metadata.job.id})

  def job_measurements(_event, measurements, metadata, owner),
    do: send(owner, {:catalog_job_measurements, metadata.job.id, measurements})
end
