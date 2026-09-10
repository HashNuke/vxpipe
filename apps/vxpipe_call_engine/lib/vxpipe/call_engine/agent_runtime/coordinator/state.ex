defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.State do
  @moduledoc false

  @derive {Inspect, only: [:provider, :maximum_pending_requests]}
  @enforce_keys [
    :agent_participant_id,
    :session,
    :invocation_registry,
    :request_supervisor,
    :owner,
    :provider,
    :maximum_output_bytes,
    :maximum_pending_requests
  ]
  defstruct @enforce_keys ++ [current: nil, pending: :queue.new()]

  @type t :: %__MODULE__{}
end
