defmodule Vxpipe.Calls.EngineLiveInspectionSource do
  @moduledoc "Reads the bounded live projection through the call engine's public API."

  @behaviour Vxpipe.Calls.LiveInspectionSource

  alias Vxpipe.CallEngine

  @impl true
  def fetch(_context, tenant_key, call_id) do
    CallEngine.inspect_live_call(tenant_key, call_id)
  end
end
