defmodule Vxpipe.Gateway.TestFailingOutgoingProjectionRepository do
  @moduledoc false
  alias Vxpipe.Calls.TestMemoryRepository

  defdelegate claim_outgoing_call(context, call, authorize), to: TestMemoryRepository
  defdelegate fetch_outgoing_by_key(context, tenant, key), to: TestMemoryRepository
  defdelegate fetch_call(context, tenant, call), to: TestMemoryRepository
  defdelegate mark_outgoing_call_failed(context, call, reason, ended), to: TestMemoryRepository

  def mark_outgoing_call_started(_context, _call, _incarnation, _started),
    do: {:error, :outgoing_projection_failed}
end
