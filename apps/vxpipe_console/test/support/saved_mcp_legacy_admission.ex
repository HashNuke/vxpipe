defmodule Vxpipe.Console.Test.SavedMCPLegacyAdmission do
  @moduledoc "Adapts the legacy three-argument startup to the current carrier fixture."

  alias Vxpipe.CallEngine
  alias Vxpipe.Gateway.CallAdmission

  # Legacy hosts start the room without an admission token. All persistence,
  # service checks, saved MCP binding, activation and execution remain real.
  def start_incoming(options, claim, service, _owner, _token) do
    with {:ok, room} <- CallAdmission.start_incoming(options, claim, service),
         {:ok, monitor} <-
           CallEngine.monitor_room(claim.call.tenant_key, claim.call.room_id, room.incarnation_id) do
      send(Keyword.fetch!(options, :legacy_observer), {:saved_mcp_legacy_started, claim.call.id})
      {:ok, room, monitor}
    end
  end

  def release_incoming(_options, _claim, _token), do: :ok

  def cancel_incoming(_options, claim, _token, _reason),
    do: CallEngine.end_call(claim.call.tenant_key, claim.call.room_id, claim.call.incarnation_id)

  defdelegate claim_incoming(options, identity, event), to: CallAdmission
  defdelegate bind_incoming(options, claim, incarnation), to: CallAdmission
  defdelegate identify_incoming(options, service, claim, room, leg), to: CallAdmission
  defdelegate prepare_incoming(options, identity), to: CallAdmission
  defdelegate submit_incoming(options, prepared), to: CallAdmission
  defdelegate end_incoming(options, service, event, activation, reason), to: CallAdmission
  defdelegate mark_incoming_started(options, claim, incarnation, time), to: CallAdmission
  defdelegate mark_incoming_failed(options, claim, reason), to: CallAdmission
  defdelegate handle_live_event(options, claim, activation, source, event), to: CallAdmission
end
