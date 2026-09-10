defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.Configuration do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{History, State}

  @default_maximum_completed_requests 32

  @spec new(keyword()) :: {:ok, State.t()} | {:error, :invalid_configuration}
  def new(options) do
    with {:ok, options} <- validate_options(options),
         {:ok, values} <- validate_values(options) do
      {:ok, build_state(values)}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  defp validate_options(options) do
    Keyword.validate(options, [
      :activation_id,
      :agent_participant_id,
      :session,
      :invocation_registry,
      :request_supervisor,
      :owner,
      :provider,
      :maximum_completed_requests,
      :maximum_output_bytes,
      :maximum_pending_requests
    ])
  end

  defp validate_values(options) do
    with activation_id when is_binary(activation_id) and activation_id != "" <-
           Keyword.get(options, :activation_id),
         agent_participant_id when is_binary(agent_participant_id) and agent_participant_id != "" <-
           Keyword.get(options, :agent_participant_id),
         session when not is_nil(session) <- Keyword.get(options, :session),
         invocation_registry when not is_nil(invocation_registry) <-
           Keyword.get(options, :invocation_registry),
         request_supervisor when not is_nil(request_supervisor) <-
           Keyword.get(options, :request_supervisor),
         owner when is_pid(owner) <- Keyword.get(options, :owner),
         maximum_completed_requests
         when is_integer(maximum_completed_requests) and maximum_completed_requests > 0 <-
           Keyword.get(
             options,
             :maximum_completed_requests,
             @default_maximum_completed_requests
           ),
         maximum_output_bytes when is_integer(maximum_output_bytes) and maximum_output_bytes > 0 <-
           Keyword.get(options, :maximum_output_bytes),
         maximum_pending_requests
         when is_integer(maximum_pending_requests) and maximum_pending_requests > 0 <-
           Keyword.get(options, :maximum_pending_requests) do
      {:ok,
       %{
         activation_id: activation_id,
         agent_participant_id: agent_participant_id,
         session: session,
         invocation_registry: invocation_registry,
         request_supervisor: request_supervisor,
         owner: owner,
         provider: Keyword.get(options, :provider, :other),
         maximum_completed_requests: maximum_completed_requests,
         maximum_output_bytes: maximum_output_bytes,
         maximum_pending_requests: maximum_pending_requests
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  defp build_state(values) do
    %State{
      agent_participant_id: values.agent_participant_id,
      completion_consumer_id: "agent-runtime-completion:" <> values.activation_id,
      session: values.session,
      invocation_registry: values.invocation_registry,
      request_supervisor: values.request_supervisor,
      owner: values.owner,
      provider: values.provider,
      history: History.new(values.maximum_completed_requests),
      maximum_output_bytes: values.maximum_output_bytes,
      maximum_pending_requests: values.maximum_pending_requests
    }
  end
end
