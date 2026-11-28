defmodule Vxpipe.CallEngine.AgentActivation.RuntimeGraph do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Protocol, Session}

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.RemoteMCP.Activation, as: RemoteActivation

  alias Vxpipe.CallEngine.AgentRuntime.{
    Coordinator,
    InvocationExecutor,
    ModelContextSource,
    PendingContextSource,
    ToolDescriptors
  }

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.CallEngine.Guardrails.RuntimeAdmission

  alias Vxpipe.CallEngine.Tool.{
    Hangup,
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor
  }

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

    with {:ok, instructions} <- instructions(options),
         {:ok, reply_protocol} <- Protocol.reply_protocol(Keyword.get(options, :agent_protocol)),
         true <- idle_protocol_supported?(Keyword.fetch!(options, :tools), reply_protocol),
         {:ok, tools} <-
           ToolDescriptors.compile(
             Keyword.fetch!(options, :tools),
             Keyword.get(options, :variable_binding),
             remote_mcp_owner,
             Keyword.get(options, :tool_announcements, false)
           ) do
      {:ok,
       [request_supervisor_child(request_supervisor)] ++
         guardrail_children(activation_id, request_supervisor, options) ++
         remote_mcp_children(activation_id, remote_mcp_owner, options) ++
         [
           coordinator_child(
             activation_id,
             coordinator,
             invocation_registry,
             request_supervisor,
             session,
             Keyword.put(options, :reply_protocol, reply_protocol)
           ),
           invocation_supervisor_child(activation_id, invocation_supervisor, options),
           invocation_registry_child(
             activation_id,
             coordinator,
             invocation_registry,
             invocation_supervisor,
             options
           ),
           session_child(
             coordinator,
             invocation_registry,
             session,
             tools,
             instructions,
             Keyword.put(options, :reply_protocol, reply_protocol)
           )
         ]}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  defp idle_protocol_supported?(tools, reply_protocol) do
    reply_protocol == :mode_message_v1 or
      not Enum.any?(tools, fn
        {_name, %{type: :platform, action: Vxpipe.CallEngine.Tool.Idle}} -> true
        _other -> false
      end)
  end

  defp request_supervisor_child(request_supervisor) do
    Supervisor.child_spec({Task.Supervisor, name: request_supervisor},
      id: :request_supervisor,
      restart: :permanent
    )
  end

  defp guardrail_children(activation_id, request_supervisor, options) do
    case Keyword.fetch(options, :guardrails) do
      :error ->
        []

      {:ok, settings} ->
        [
          Vxpipe.CallEngine.Guardrails.Participant.activation_child(
            activation_id,
            request_supervisor,
            settings
          )
        ]
    end
  end

  defp remote_mcp_owner(activation_id, options) do
    if RemoteActivation.selected?(Keyword.fetch!(options, :tools)) do
      child_ref(activation_id, :remote_mcp_owner)
    end
  end

  defp remote_mcp_children(_activation_id, nil, _options), do: []

  defp remote_mcp_children(activation_id, remote_mcp_owner, options) do
    sessions = child_ref(activation_id, :remote_mcp_sessions)

    owner_options = [
      activation_id: activation_id,
      session_supervisor: sessions,
      lifecycle_owner: Keyword.fetch!(options, :owner),
      initialization: Keyword.get(options, :mcp_initialization),
      participant_id: Keyword.fetch!(options, :agent_participant_id),
      tools: Keyword.fetch!(options, :tools),
      integrations: Keyword.get(options, :mcp_integrations),
      name: remote_mcp_owner
    ]

    owner_options =
      owner_options
      |> put_optional(
        :connection_provider,
        Keyword.get(options, :remote_mcp_connection_provider)
      )
      |> put_optional(:protocol, Keyword.get(options, :remote_mcp_protocol_client))

    owner_options
    |> RemoteActivation.children()
    |> Enum.map(&Supervisor.child_spec(&1, restart: :permanent))
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
       history_mode: Keyword.get(options, :history_mode, :generated),
       reply_protocol: Keyword.fetch!(options, :reply_protocol),
       invocation_registry: invocation_registry,
       request_supervisor: request_supervisor,
       remote_mcp_owner: remote_mcp_owner(activation_id, options),
       owner: Keyword.fetch!(options, :owner),
       provider: Keyword.get(options, :provider, :other),
       usage_provider: Keyword.fetch!(options, :usage_provider),
       maximum_completed_requests: Keyword.fetch!(options, :maximum_completed_requests),
       maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
       maximum_pending_requests: Keyword.fetch!(options, :maximum_pending_requests),
       guardrails: coordinator_guardrails(activation_id, options),
       request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
       name: coordinator},
      id: :coordinator,
      restart: :permanent
    )
  end

  defp coordinator_guardrails(activation_id, options) do
    case Keyword.fetch(options, :guardrails) do
      {:ok, _settings} -> child_ref(activation_id, :guardrails)
      :error -> nil
    end
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
       participant_id: Keyword.fetch!(options, :agent_participant_id),
       invocation_supervisor: invocation_supervisor,
       completion_target: coordinator,
       lifecycle_target: Keyword.fetch!(options, :owner),
       maximum_invocations: Keyword.fetch!(options, :maximum_tool_invocations),
       maximum_consumed_invocations: Keyword.fetch!(options, :maximum_completed_requests),
       invocation_timeout_ms: Keyword.fetch!(options, :tool_invocation_timeout_ms),
       maximum_result_bytes: Keyword.fetch!(options, :maximum_tool_result_bytes),
       usage: [call_id: Keyword.fetch!(options, :call_id), activation_id: activation_id],
       name: invocation_registry},
      id: :invocation_registry,
      restart: :permanent
    )
  end

  defp instructions(options) do
    authored = Keyword.fetch!(options, :system_prompt)

    snapshot = Keyword.get(options, :agent_protocol)

    with {:ok, instructions} <- Protocol.instructions(snapshot, authored, :llm) do
      if match?(%{"version" => "mode_message_v1"}, snapshot) do
        identity = JSON.encode!(Keyword.fetch!(options, :agent_participant_id))
        {:ok, instructions <> "\n\nCurrent agent participant_id: " <> identity <> "."}
      else
        {:ok, instructions}
      end
    end
  end

  defp session_child(coordinator, invocation_registry, session, tools, instructions, options) do
    activation_id = Keyword.fetch!(options, :activation_id)

    session_options = [
      instructions: instructions,
      history_mode: Keyword.get(options, :history_mode, :generated),
      reply_protocol: Keyword.fetch!(options, :reply_protocol),
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
      round_admission: round_admission(activation_id, tools, options),
      maximum_admission_repairs: Keyword.get(options, :maximum_admission_repairs, 2),
      name: session
    ]

    session_options =
      session_options
      |> put_optional(:initial_messages, Keyword.get(options, :initial_messages))
      |> put_optional(
        :model_context_source,
        model_context_source(Keyword.get(options, :model_context_source), coordinator)
      )
      |> put_optional(:context_compaction, compaction_options(options))

    Supervisor.child_spec(
      {Session, session_options},
      id: :session,
      restart: :permanent
    )
  end

  defp compaction_options(options) do
    compaction = Keyword.get(options, :context_compaction)
    snapshot = Keyword.get(options, :agent_protocol)

    if snapshot != nil and is_list(compaction) and Keyword.get(compaction, :enabled, false) do
      {:ok, prompt} = Protocol.summary_prompt(snapshot)
      Keyword.put(compaction, :summary_prompt, prompt)
    else
      compaction
    end
  end

  defp child_ref(activation_id, role),
    do: AgentActivationSupervisor.child_ref(activation_id, role)

  defp model_context_source(nil, coordinator) do
    model_context_source(
      %ModelContextSource{variable_binding: nil, transfer_reason: nil},
      coordinator
    )
  end

  defp model_context_source(%ModelContextSource{} = source, coordinator),
    do: {ModelContextSource, ModelContextSource.with_coordinator(source, coordinator)}

  defp put_optional(options, _key, nil), do: options
  defp put_optional(options, key, value), do: Keyword.put(options, key, value)

  # Actual engine host bridge: `nil` without guardrails, otherwise a
  # domain-neutral `RoundAdmission` callback into participant guardrails.
  # Terminal kinds come from `%InvocationBinding{}` handlers (binding-derived),
  # never from hardcoded tool names.
  defp round_admission(activation_id, tools, options) do
    case Keyword.fetch(options, :guardrails) do
      :error ->
        nil

      {:ok, settings} when is_list(settings) ->
        policy = Keyword.fetch!(settings, :policy)

        {RuntimeAdmission,
         %{
           guardrails: AgentActivationSupervisor.child_ref(activation_id, :guardrails),
           activation_id: activation_id,
           agent_participant_id: Keyword.get(options, :agent_participant_id),
           incarnation_id: Keyword.get(options, :incarnation_id, activation_id),
           room_authority: room_authority(options),
           after_questions: policy.after_turn,
           transfer_questions: policy.before_outgoing_transfer,
           policy_revision: Keyword.get(settings, :policy_revision),
           terminal_kinds: terminal_kinds(tools),
           maximum_feedback_bytes: Keyword.get(options, :maximum_model_context_bytes, 256 * 1_024)
         }}
    end
  end

  defp room_authority(options) do
    with tenant when is_binary(tenant) and tenant != "" <- Keyword.get(options, :tenant_id),
         room when is_binary(room) and room != "" <- Keyword.get(options, :room_id) do
      {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {tenant, room}}}
    else
      _missing -> nil
    end
  end

  defp terminal_kinds(tools) when is_list(tools) do
    Map.new(tools, fn %ToolDescriptor{} = descriptor ->
      {descriptor.name, terminal_kind(descriptor.binding)}
    end)
  end

  defp terminal_kind(%InvocationBinding{handler: {:participant_transfer, _}}), do: :transfer
  defp terminal_kind(%InvocationBinding{handler: {:platform, Hangup}}), do: :hangup
  defp terminal_kind(_binding), do: :ordinary
end
