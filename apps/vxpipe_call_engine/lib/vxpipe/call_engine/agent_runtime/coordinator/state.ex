defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.State do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{History, UsageRounds}
  alias Vxpipe.CallEngine.Usage.ProviderContext

  @derive {Inspect, only: [:provider, :maximum_pending_requests]}
  @enforce_keys [
    :agent_participant_id,
    :activation_id,
    :call_id,
    :completion_consumer_id,
    :session,
    :invocation_registry,
    :request_supervisor,
    :owner,
    :provider,
    :usage_provider,
    :usage_rounds,
    :history,
    :maximum_output_bytes,
    :maximum_pending_requests
  ]
  defstruct @enforce_keys ++
              [
                current: nil,
                readiness_resource: nil,
                remote_mcp_owner: nil,
                pending: :queue.new(),
                completion_deferred?: false
              ]

  @type t :: %__MODULE__{
          activation_id: String.t(),
          call_id: String.t(),
          history: History.t(),
          usage_provider: ProviderContext.t(),
          usage_rounds: UsageRounds.t(),
          completion_deferred?: boolean()
        }
end
