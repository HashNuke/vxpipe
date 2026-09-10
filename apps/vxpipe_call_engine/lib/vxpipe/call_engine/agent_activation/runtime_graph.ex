defmodule Vxpipe.CallEngine.AgentActivation.RuntimeGraph do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session

  alias Vxpipe.CallEngine.AgentActivationSupervisor

  alias Vxpipe.CallEngine.AgentRuntime.{
    Coordinator,
    InvocationExecutor,
    PendingContextSource,
    ToolDescriptors
  }

  alias Vxpipe.CallEngine.Tool.{InvocationRegistry, InvocationSupervisor}

  @spec children(keyword()) ::
          {:ok, [Supervisor.child_spec()]} | {:error, :invalid_configuration}
  def children(options) do
    activation_id = Keyword.fetch!(options, :activation_id)
    coordinator = child_ref(activation_id, :coordinator)
    invocation_registry = child_ref(activation_id, :invocation_registry)
    invocation_supervisor = child_ref(activation_id, :invocation_supervisor)
    request_supervisor = child_ref(activation_id, :request_supervisor)
    session = child_ref(activation_id, :session)

    with {:ok, tools} <-
           ToolDescriptors.compile(
             Keyword.fetch!(options, :tools),
             Keyword.get(options, :variable_binding)
           ) do
      {:ok,
       [
         request_supervisor_child(request_supervisor),
         coordinator_child(
           activation_id,
           coordinator,
           invocation_registry,
           request_supervisor,
           session,
           options
         ),
         invocation_supervisor_child(activation_id, invocation_supervisor, options),
         invocation_registry_child(
           activation_id,
           coordinator,
           invocation_registry,
           invocation_supervisor,
           options
         ),
         session_child(coordinator, invocation_registry, session, tools, options)
       ]}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  defp request_supervisor_child(request_supervisor) do
    Supervisor.child_spec({Task.Supervisor, name: request_supervisor},
      id: :request_supervisor,
      restart: :permanent
    )
  end

  defp coordinator_child(
         activation_id,
         coordinator,
         invocation_registry,
         request_supervisor,
         session,
         options
       ) do
    Supervisor.child_spec(
      {Coordinator,
       activation_id: activation_id,
       agent_participant_id: Keyword.fetch!(options, :agent_participant_id),
       session: session,
       invocation_registry: invocation_registry,
       request_supervisor: request_supervisor,
       owner: Keyword.fetch!(options, :owner),
       provider: Keyword.get(options, :provider, :other),
       maximum_completed_requests: Keyword.fetch!(options, :maximum_completed_requests),
       maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
       maximum_pending_requests: Keyword.fetch!(options, :maximum_pending_requests),
       name: coordinator},
      id: :coordinator,
      restart: :permanent
    )
  end

  defp invocation_supervisor_child(activation_id, invocation_supervisor, options) do
    Supervisor.child_spec(
      {InvocationSupervisor,
       activation_id: activation_id,
       maximum_children: Keyword.fetch!(options, :maximum_background_tools),
       name: invocation_supervisor},
      id: :invocation_supervisor,
      restart: :permanent
    )
  end

  defp invocation_registry_child(
         activation_id,
         coordinator,
         invocation_registry,
         invocation_supervisor,
         options
       ) do
    Supervisor.child_spec(
      {InvocationRegistry,
       activation_id: activation_id,
       invocation_supervisor: invocation_supervisor,
       completion_target: coordinator,
       lifecycle_target: Keyword.fetch!(options, :owner),
       maximum_invocations: Keyword.fetch!(options, :maximum_background_tools),
       maximum_consumed_invocations: Keyword.fetch!(options, :maximum_completed_requests),
       invocation_timeout_ms: Keyword.fetch!(options, :background_tool_timeout_ms),
       maximum_result_bytes: Keyword.fetch!(options, :maximum_tool_result_bytes),
       name: invocation_registry},
      id: :invocation_registry,
      restart: :permanent
    )
  end

  defp session_child(coordinator, invocation_registry, session, tools, options) do
    Supervisor.child_spec(
      {Session,
       instructions: Keyword.fetch!(options, :system_prompt),
       model_provider: Keyword.fetch!(options, :model_provider),
       model: Keyword.get(options, :model),
       tools: tools,
       executor: InvocationExecutor,
       pending_context_source: {PendingContextSource, invocation_registry},
       maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
       maximum_pending_invocations: Keyword.fetch!(options, :maximum_background_tools),
       request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
       event_destination: coordinator,
       name: session},
      id: :session,
      restart: :permanent
    )
  end

  defp child_ref(activation_id, role),
    do: AgentActivationSupervisor.child_ref(activation_id, role)
end
