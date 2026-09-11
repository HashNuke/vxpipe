defmodule Vxpipe.CallEngine.AgentActivation.RuntimeGraph do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.RemoteMCP.{IntegrationCatalog, IntegrationOwner}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

  alias Vxpipe.CallEngine.AgentRuntime.{
    Coordinator,
    InvocationExecutor,
    ModelContextSource,
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
    remote_mcp_owner = remote_mcp_owner(activation_id, options)
    request_supervisor = child_ref(activation_id, :request_supervisor)
    session = child_ref(activation_id, :session)

    with {:ok, tools} <-
           ToolDescriptors.compile(
             Keyword.fetch!(options, :tools),
             Keyword.get(options, :variable_binding),
             remote_mcp_owner
           ) do
      {:ok,
       [request_supervisor_child(request_supervisor)] ++
         remote_mcp_children(activation_id, remote_mcp_owner, options) ++
         [
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

  defp remote_mcp_owner(activation_id, options) do
    if remote_mcp_tools?(Keyword.fetch!(options, :tools)) do
      child_ref(activation_id, :remote_mcp_owner)
    end
  end

  defp remote_mcp_tools?(tools) do
    Enum.any?(tools, fn
      {_name, %ToolBinding{type: :mcp}} -> true
      _entry -> false
    end)
  end

  defp remote_mcp_children(_activation_id, nil, _options), do: []

  defp remote_mcp_children(activation_id, remote_mcp_owner, options) do
    with %IntegrationCatalog{} = integrations <- Keyword.get(options, :mcp_integrations) do
      owner_options = [
        activation_id: activation_id,
        tools: Keyword.fetch!(options, :tools),
        integrations: integrations,
        name: remote_mcp_owner
      ]

      owner_options =
        owner_options
        |> put_optional(
          :connection_provider,
          Keyword.get(options, :remote_mcp_connection_provider)
        )
        |> put_optional(:protocol, Keyword.get(options, :remote_mcp_protocol_client))

      [
        Supervisor.child_spec({IntegrationOwner, owner_options},
          id: :remote_mcp_owner,
          restart: :permanent
        )
      ]
    else
      _invalid -> raise ArgumentError, "remote MCP integrations are unavailable"
    end
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
       call_id: Keyword.fetch!(options, :call_id),
       session: session,
       invocation_registry: invocation_registry,
       request_supervisor: request_supervisor,
       owner: Keyword.fetch!(options, :owner),
       provider: Keyword.get(options, :provider, :other),
       usage_provider: Keyword.fetch!(options, :usage_provider),
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
       maximum_children: Keyword.fetch!(options, :maximum_tool_invocations),
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
       maximum_invocations: Keyword.fetch!(options, :maximum_tool_invocations),
       maximum_consumed_invocations: Keyword.fetch!(options, :maximum_completed_requests),
       invocation_timeout_ms: Keyword.fetch!(options, :tool_invocation_timeout_ms),
       maximum_result_bytes: Keyword.fetch!(options, :maximum_tool_result_bytes),
       name: invocation_registry},
      id: :invocation_registry,
      restart: :permanent
    )
  end

  defp session_child(coordinator, invocation_registry, session, tools, options) do
    session_options = [
      instructions: Keyword.fetch!(options, :system_prompt),
      model_provider: Keyword.fetch!(options, :model_provider),
      model: Keyword.get(options, :model),
      tools: tools,
      executor: InvocationExecutor,
      pending_context_source: {PendingContextSource, invocation_registry},
      maximum_model_context_bytes:
        Keyword.get(options, :maximum_model_context_bytes, 256 * 1_024),
      model_context_timeout_ms: Keyword.get(options, :model_context_timeout_ms, 1_000),
      maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
      maximum_pending_invocations: Keyword.fetch!(options, :maximum_tool_invocations),
      request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
      event_destination: coordinator,
      name: session
    ]

    session_options =
      session_options
      |> put_optional(:initial_messages, Keyword.get(options, :initial_messages))
      |> put_optional(
        :model_context_source,
        model_context_source(Keyword.get(options, :model_context_source))
      )

    Supervisor.child_spec(
      {Session, session_options},
      id: :session,
      restart: :permanent
    )
  end

  defp child_ref(activation_id, role),
    do: AgentActivationSupervisor.child_ref(activation_id, role)

  defp model_context_source(nil), do: nil

  defp model_context_source(%ModelContextSource{} = source),
    do: {ModelContextSource, source}

  defp put_optional(options, _key, nil), do: options
  defp put_optional(options, key, value), do: Keyword.put(options, key, value)
end
