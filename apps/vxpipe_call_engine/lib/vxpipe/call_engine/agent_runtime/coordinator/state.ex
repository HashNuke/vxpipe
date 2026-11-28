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
                pending_literal: nil,
                history_mode: :generated,
                reply_protocol: :legacy,
                awaiting_output: nil,
                held_output: nil,
                readiness_resource: nil,
                remote_mcp_owner: nil,
                pending: :queue.new(),
                idle_pause: nil,
                idle_invocations: MapSet.new(),
                completion_deferred?: false,
                guardrails: nil,
                request_timeout_ms: nil
              ]

  @type t :: %__MODULE__{
          activation_id: String.t(),
          call_id: String.t(),
          history: History.t(),
          usage_provider: ProviderContext.t(),
          usage_rounds: UsageRounds.t(),
          completion_deferred?: boolean()
        }

  def request_options(state) do
    [
      agent_participant_id: state.agent_participant_id,
      invocation_registry: state.invocation_registry,
      maximum_output_bytes: state.maximum_output_bytes,
      request_supervisor: state.request_supervisor,
      session: state.session,
      guardrails: state.guardrails,
      request_timeout_ms: state.request_timeout_ms
    ]
  end

  def request_outcome_options(state) do
    [
      session: state.session,
      invocation_registry: state.invocation_registry,
      owner: state.owner,
      provider: state.provider
    ]
  end
end
