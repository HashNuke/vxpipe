defmodule Vxpipe.Persistence.CallCleanupScanStore do
  @moduledoc "Finite keyset cycles over unresolved call cleanup, without loading call plans."

  import Ecto.Query
  alias Vxpipe.Calls.CallCleanupScan
  alias Vxpipe.Persistence.Schema.Call

  def scan(repo, cursor, limit) do
    if CallCleanupScan.valid_request?(cursor, limit),
      do: page(repo, cursor || initial_cursor(repo), limit),
      else: {:error, :invalid_cleanup_scan}
  end

  defp initial_cursor(repo), do: %{after_id: 0, through_id: repo.aggregate(Call, :max, :id) || 0}

  defp page(repo, cursor, limit) do
    items =
      repo.all(
        from(call in Call,
          join: tenant in assoc(call, :tenant),
          where: call.id > ^cursor.after_id and call.id <= ^cursor.through_id,
          where:
            call.state != :ended and
              (not is_nil(call.hangup_requested_at) or
                 (call.gateway_cleanup_required and is_nil(call.gateway_cleanup_completed_at))),
          order_by: [asc: call.id],
          limit: ^limit,
          select: %{
            id: call.id,
            tenant_key: tenant.key,
            call_id: call.public_id,
            room_id: call.room_id,
            incarnation_id: call.incarnation_id,
            incarnation_binding_verified: call.incarnation_binding_verified,
            hangup_requested_at: call.hangup_requested_at,
            gateway_cleanup_required: call.gateway_cleanup_required,
            gateway_cleanup_completed_at: call.gateway_cleanup_completed_at
          }
        )
      )

    next =
      case List.last(items) do
        %{id: id} when length(items) == limit and id < cursor.through_id ->
          %{cursor | after_id: id}

        _cycle_finished ->
          nil
      end

    {:ok, %{items: items, next_cursor: next}}
  end
end
