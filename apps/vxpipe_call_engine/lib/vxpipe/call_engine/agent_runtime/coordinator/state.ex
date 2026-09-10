defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.State do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.History

  @derive {Inspect, only: [:provider, :maximum_pending_requests]}
  @enforce_keys [
    :agent_participant_id,
    :completion_consumer_id,
    :session,
    :invocation_registry,
    :request_supervisor,
    :owner,
    :provider,
    :history,
    :maximum_output_bytes,
    :maximum_pending_requests
  ]
  defstruct @enforce_keys ++ [current: nil, pending: :queue.new()]

  @type t :: %__MODULE__{history: History.t()}
end
