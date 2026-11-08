defmodule Vxpipe.Persistence.Test.CatalogJobNode do
  @moduledoc "Runs the configured catalog worker and orphan recovery in an isolated BEAM."
  alias Vxpipe.Persistence.{Repo, Test.MCPDatabaseNode}
  alias Vxpipe.Persistence.MCP.{CatalogRefreshStore, ConnectionStore}

  def boot(repository, context, endpoint, rescue?) do
    identity = MCPDatabaseNode.boot(repository)
    Logger.configure(level: :warning)
    {:ok, _} = Application.ensure_all_started(:vxpipe_mcp)
    {:ok, _} = Application.ensure_all_started(:oban)
    :ok = Application.load(:vxpipe_persistence)
    context = context |> Keyword.put(:repo, Repo) |> Keyword.put(:oban, __MODULE__.Jobs)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      mcp_catalog_refresh_repository: {CatalogRefreshStore, context},
      mcp_connection_repository: {ConnectionStore, context}
    )

    Application.put_env(
      :vxpipe_calls,
      :mcp_catalog_protocol,
      {Vxpipe.Persistence.Test.CatalogDiscoveryProtocol, [endpoint: endpoint]}
    )

    {:ok, _} =
      Supervisor.start_child(
        Vxpipe.MCP.Supervisor,
        {DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.Host}
      )

    options = [
      name: __MODULE__.Jobs,
      repo: Repo,
      node: System.pid(),
      notifier: {Oban.Notifiers.PG, []},
      peer: {Oban.Peers.Isolated, [leader?: true]},
      queues: [mcp_catalog: 1]
    ]

    options =
      if rescue?,
        do: Keyword.put(options, :lifeline, interval: 50, rescue_after: {5, :minutes}),
        else: options

    {:ok, _} = DynamicSupervisor.start_child(__MODULE__.Host, {Oban, options})
    identity
  end

  def await_job(id) do
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, [:oban, :job, :stop], &__MODULE__.completed/4, {self(), id})

    try do
      job = Repo.get!(Oban.Job, id)

      if job.state == "completed" do
        %{state: job.state, attempt: job.attempt}
      else
        receive do
          :catalog_job_completed ->
            finished = Repo.get!(Oban.Job, id)
            %{state: finished.state, attempt: finished.attempt}
        after
          5_000 -> {:error, :catalog_job_not_completed}
        end
      end
    after
      :telemetry.detach(handler)
    end
  end

  def completed(_event, _measurements, metadata, {owner, id}) do
    if metadata.job.id == id, do: send(owner, :catalog_job_completed)
  end
end
