defmodule Vxpipe.Persistence.MCP.CatalogRefreshStore do
  @moduledoc "Atomic metadata-only catalog scheduling on the existing Repo and Oban instance."
  @behaviour Vxpipe.Calls.MCPCatalogRefreshRepository

  import Ecto.Query
  alias Vxpipe.Persistence.MCP.{CatalogRefreshWorker, ConnectionStore, RepositoryBoundary}
  alias Vxpipe.Persistence.Schema.MCPConnection

  @private [log: false, telemetry_event: nil]
  @incomplete Enum.map(Oban.Job.unique_states(:incomplete), &Atom.to_string/1)

  @impl true
  def enqueue_due(context, policy) do
    RepositoryBoundary.call(
      fn ->
        repo = Keyword.fetch!(context, :repo)
        oban = Keyword.get(context, :oban, Vxpipe.Persistence.Jobs)
        config = Oban.config(oban)

        if config.repo == repo do
          repo.transaction(
            fn -> enqueue_locked(repo, oban, config.prefix, context, policy) end,
            @private
          )
        else
          {:error, :invalid_catalog_queue_repository}
        end
      end,
      :mcp_catalog_refresh_unavailable
    )
  end

  defp enqueue_locked(repo, oban, prefix, context, policy) do
    now = ConnectionStore.catalog_time(context)
    expiry = DateTime.add(now, -Keyword.fetch!(policy, :expiry_seconds))
    scheduling = DateTime.add(now, -Keyword.fetch!(policy, :reschedule_after_seconds))
    worker = Oban.Worker.to_string(CatalogRefreshWorker)

    incomplete =
      from(j in Oban.Job,
        prefix: ^prefix,
        where: j.worker == ^worker and j.state in @incomplete,
        where:
          fragment(
            "? @> jsonb_build_object('tenant', ?::text, 'connection_id', ?::text, 'generation', ?::bigint)",
            j.args,
            parent_as(:tenant).key,
            parent_as(:connection).public_id,
            parent_as(:connection).generation
          ),
        select: 1
      )

    query =
      from(c in MCPConnection,
        as: :connection,
        join: t in assoc(c, :tenant),
        as: :tenant,
        where: c.status == "connected",
        where: is_nil(c.refreshed_at) or c.refreshed_at <= ^expiry,
        where: is_nil(c.refresh_scheduled_at) or c.refresh_scheduled_at <= ^scheduling,
        where: not exists(subquery(incomplete)),
        order_by: c.id,
        limit: ^Keyword.fetch!(policy, :batch_size),
        lock: fragment("FOR UPDATE OF ? SKIP LOCKED", c),
        select: {c, t.key}
      )

    repo.all(query, @private)
    |> Enum.reduce(0, fn {record, tenant}, count ->
      args = %{
        "tenant" => tenant,
        "connection_id" => record.public_id,
        "generation" => record.generation,
        "scheduled_at" => DateTime.to_iso8601(now)
      }

      case Oban.insert(oban, CatalogRefreshWorker.new(args)) do
        {:ok, %Oban.Job{conflict?: false}} ->
          record
          |> Ecto.Changeset.change(refresh_scheduled_at: now)
          |> repo.update!(@private)

          count + 1

        {:ok, %Oban.Job{conflict?: true}} ->
          count

        {:error, _reason} ->
          repo.rollback(:mcp_catalog_enqueue_failed)
      end
    end)
  end

  @impl true
  def fetch_due(context, args, policy) do
    with {:ok, record} <-
           ConnectionStore.get_retained(context, args["tenant"], args["connection_id"]),
         {:ok, scheduled, 0} <- DateTime.from_iso8601(args["scheduled_at"]) do
      expiry =
        DateTime.add(
          ConnectionStore.catalog_time(context),
          -Keyword.fetch!(policy, :expiry_seconds)
        )

      if record.status == "connected" and record.generation == args["generation"] and
           record.refresh_scheduled_at == scheduled and
           (is_nil(record.refreshed_at) or DateTime.compare(record.refreshed_at, expiry) != :gt),
         do: {:ok, record},
         else: {:ok, :obsolete}
    else
      {:error, :mcp_connection_not_found} -> {:ok, :obsolete}
      error -> error
    end
  end
end
