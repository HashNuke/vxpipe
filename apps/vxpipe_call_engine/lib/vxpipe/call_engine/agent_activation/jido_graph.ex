defmodule Vxpipe.CallEngine.AgentActivation.JidoGraph do
  @moduledoc false

  alias Vxpipe.CallEngine.{Agent, AgentActivationSupervisor, AgentCoordinator, JidoAgentRuntime}
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.Tool.{BackgroundSupervisor, Dispatcher}

  @spec children(keyword()) :: [Supervisor.child_spec()]
  def children(options) do
    activation_id = Keyword.fetch!(options, :activation_id)
    agent_server = child_ref(activation_id, :agent_server)
    background_tools = child_ref(activation_id, :background_tools)
    coordinator = child_ref(activation_id, :coordinator)
    tool_dispatcher = child_ref(activation_id, :tool_dispatcher)
    {remote_mcp, remote_tools, remote_mcp_children} = remote_mcp_runtime(activation_id, options)

    [
      background_tools_child(activation_id, background_tools, options)
      | remote_mcp_children
    ] ++
      [
        dispatcher_child(
          activation_id,
          background_tools,
          coordinator,
          tool_dispatcher,
          remote_mcp,
          remote_tools,
          options
        ),
        agent_server_child(activation_id, agent_server),
        coordinator_child(activation_id, agent_server, coordinator, tool_dispatcher, options)
      ]
  end

  defp background_tools_child(activation_id, background_tools, options) do
    Supervisor.child_spec(
      {BackgroundSupervisor,
       activation_id: activation_id,
       maximum_children: Keyword.get(options, :maximum_background_tools, 4),
       name: background_tools},
      id: :background_tools,
      restart: :permanent
    )
  end

  defp dispatcher_child(
         activation_id,
         background_tools,
         coordinator,
         tool_dispatcher,
         remote_mcp,
         remote_tools,
         options
       ) do
    Supervisor.child_spec(
      {Dispatcher,
       activation_id: activation_id,
       background_supervisor: background_tools,
       background_tool_timeout_ms: Keyword.get(options, :background_tool_timeout_ms, 30_000),
       completion_target: coordinator,
       name: tool_dispatcher,
       remote_mcp: remote_mcp,
       remote_tools: Map.keys(remote_tools),
       tools: Keyword.fetch!(options, :tools),
       variable_binding: Keyword.get(options, :variable_binding),
       maximum_background_tools: Keyword.get(options, :maximum_background_tools, 4),
       maximum_result_bytes: Keyword.fetch!(options, :maximum_tool_result_bytes)},
      id: :tool_dispatcher,
      restart: :permanent
    )
  end

  defp agent_server_child(activation_id, agent_server) do
    Supervisor.child_spec(
      {Jido.AgentServer,
       agent: Agent,
       id: activation_id,
       jido: Vxpipe.CallEngine.Jido,
       name: agent_server,
       register_global: false},
      id: :agent_server,
      restart: :permanent
    )
  end

  defp coordinator_child(activation_id, agent_server, coordinator, tool_dispatcher, options) do
    Supervisor.child_spec(
      {AgentCoordinator,
       activation_id: activation_id,
       agent_participant_id: Keyword.fetch!(options, :agent_participant_id),
       agent_server: agent_server,
       agent_runtime: JidoAgentRuntime,
       owner: Keyword.fetch!(options, :owner),
       provider: Keyword.get(options, :provider, :other),
       tool_dispatcher: tool_dispatcher,
       maximum_background_completions: Keyword.get(options, :maximum_background_tools, 4),
       maximum_completed_requests: Keyword.fetch!(options, :maximum_completed_requests),
       maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
       maximum_pending_requests: Keyword.fetch!(options, :maximum_pending_requests),
       request_options: Keyword.fetch!(options, :request_options),
       request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
       agent_configuration: [
         system_prompt: Keyword.fetch!(options, :system_prompt),
         tools: Keyword.fetch!(options, :tools)
       ],
       name: coordinator},
      id: :coordinator,
      restart: :permanent
    )
  end

  defp remote_mcp_runtime(activation_id, options) do
    tools = Keyword.get(options, :remote_tools, %{})

    if map_size(tools) == 0 do
      {nil, tools, []}
    else
      owner = child_ref(activation_id, :remote_mcp)

      owner_options =
        [
          activation_id: activation_id,
          integrations: Keyword.get(options, :mcp_integrations),
          name: owner,
          tools: tools
        ]
        |> maybe_put(
          :connection_provider,
          Keyword.fetch(options, :remote_mcp_connection_provider)
        )
        |> maybe_put(:protocol, Keyword.fetch(options, :remote_mcp_protocol))

      child =
        Supervisor.child_spec({IntegrationOwner, owner_options},
          id: :remote_mcp,
          restart: :permanent
        )

      {owner, tools, [child]}
    end
  end

  defp child_ref(activation_id, role),
    do: AgentActivationSupervisor.child_ref(activation_id, role)

  defp maybe_put(options, key, {:ok, value}), do: Keyword.put(options, key, value)
  defp maybe_put(options, _key, :error), do: options
end
