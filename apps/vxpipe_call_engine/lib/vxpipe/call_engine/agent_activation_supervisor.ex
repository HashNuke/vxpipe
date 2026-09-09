defmodule Vxpipe.CallEngine.AgentActivationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.{Agent, AgentCoordinator, JidoAgentRuntime}
  alias Vxpipe.CallEngine.Tool.{BackgroundSupervisor, Dispatcher}

  @roles [:agent_server, :background_tools, :coordinator, :tool_dispatcher]

  def start_link(options) do
    activation_id = Keyword.fetch!(options, :activation_id)
    Supervisor.start_link(__MODULE__, options, name: via(activation_id, :supervisor))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @spec children(Supervisor.supervisor()) :: %{atom() => pid()}
  def children(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Map.new(fn {role, pid, _type, _modules} -> {role, pid} end)
  end

  @spec whereis_child(String.t(), atom()) :: pid() | nil
  def whereis_child(activation_id, role)
      when is_binary(activation_id) and role in @roles do
    GenServer.whereis(child_ref(activation_id, role))
  end

  @spec child_ref(String.t(), atom()) :: GenServer.server()
  def child_ref(activation_id, role)
      when is_binary(activation_id) and role in @roles do
    via(activation_id, role)
  end

  @impl true
  def init(options) do
    activation_id = Keyword.fetch!(options, :activation_id)
    agent_server = via(activation_id, :agent_server)
    background_tools = via(activation_id, :background_tools)
    coordinator = via(activation_id, :coordinator)
    tool_dispatcher = via(activation_id, :tool_dispatcher)

    background_tools_child =
      Supervisor.child_spec(
        {BackgroundSupervisor,
         activation_id: activation_id,
         maximum_children: Keyword.get(options, :maximum_background_tools, 4),
         name: background_tools},
        id: :background_tools,
        restart: :permanent
      )

    dispatcher_child =
      Supervisor.child_spec(
        {Dispatcher,
         activation_id: activation_id,
         background_supervisor: background_tools,
         background_tool_timeout_ms: Keyword.get(options, :background_tool_timeout_ms, 30_000),
         completion_target: coordinator,
         name: tool_dispatcher,
         tools: Keyword.fetch!(options, :tools),
         variable_binding: Keyword.get(options, :variable_binding),
         maximum_background_tools: Keyword.get(options, :maximum_background_tools, 4),
         maximum_result_bytes: Keyword.fetch!(options, :maximum_tool_result_bytes)},
        id: :tool_dispatcher,
        restart: :permanent
      )

    agent_server_child =
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

    coordinator_child =
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

    Supervisor.init(
      [background_tools_child, dispatcher_child, agent_server_child, coordinator_child],
      strategy: :one_for_all,
      max_restarts: 1,
      max_seconds: 5
    )
  end

  defp via(activation_id, role) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, registry_key(activation_id, role)}}
  end

  defp registry_key(activation_id, role), do: {:agent_activation, activation_id, role}
end
