defmodule Vxpipe.Persistence.InspectionStore do
  @moduledoc "Ecto adapter for bounded, tenant-scoped call inspection reads."

  @behaviour Vxpipe.Calls.InspectionRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallListCursor, CallSummary}
  alias Vxpipe.Persistence.Schema.{Call, CallDefinition, DefinitionRevision, Tenant}

  @impl true
  def list_calls(repo, tenant_key, limit, cursor) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        join: revision in DefinitionRevision,
        on: revision.id == call.definition_revision_id,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: call.created_at, desc: call.public_id],
        limit: ^limit,
        select: {call, definition.public_id, revision.revision}
      )

    calls =
      query
      |> after_cursor(cursor)
      |> repo.all()
      |> Enum.map(&to_summary(&1, tenant_key))

    {:ok, calls}
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, %CallListCursor{} = cursor) do
    from([call, _tenant, _revision, _definition] in query,
      where:
        call.created_at < ^cursor.created_at or
          (call.created_at == ^cursor.created_at and call.public_id < ^cursor.call_id)
    )
  end

  defp to_summary({call, definition_id, definition_revision}, tenant_key) do
    %CallSummary{
      id: call.public_id,
      tenant_key: tenant_key,
      definition_id: definition_id,
      definition_revision: definition_revision,
      state: call.state,
      created_at: call.created_at,
      started_at: call.started_at,
      ended_at: call.ended_at,
      terminal_reason: call.terminal_reason
    }
  end
end
