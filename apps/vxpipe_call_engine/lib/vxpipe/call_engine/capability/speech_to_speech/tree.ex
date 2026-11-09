defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree do
  @moduledoc "Agent-owned temporary subtree for one speech-to-speech allocation."

  use Supervisor

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.ToolCompletions
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RemoteMCP.Activation, as: RemoteActivation
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, PrivateInit}
  alias Vxpipe.CallEngine.Tool.{InvocationConfig, InvocationRegistry, InvocationSupervisor}

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :agent_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  def capability(tree) do
    tree
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {SpeechToSpeech, pid, :worker, _modules} -> pid
      _child -> nil
    end)
  end

  def parent(capability) when is_pid(capability) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {__MODULE__, :parent, capability}) do
      [{tree, nil}] -> tree
      [] -> nil
    end
  end

  def invocation_registry(capability), do: child(capability, :invocation_registry)
  def invocation_supervisor(capability), do: child(capability, :invocation_supervisor)
  def tool_completions(capability), do: child(capability, :tool_completions)
  def remote_mcp_owner(capability), do: child(capability, :remote_mcp_owner)
  def remote_mcp_sessions(capability), do: child(capability, :remote_mcp_sessions)

  defp child(capability, kind) do
    case parent(capability) do
      nil -> nil
      tree -> GenServer.whereis(address(tree, kind))
    end
  end

  @impl true
  def init(options) do
    scope_name = address(self(), :scope)
    output_scope_name = address(self(), :output_stt_scope)
    output_stt? = Keyword.has_key?(options, :output_stt)
    output_tasks = address(self(), :output_tasks)
    options = Keyword.put(options, :output_task_supervisor, output_tasks)
    remote_owner = if Keyword.get(options, :remote_mcp), do: address(self(), :remote_mcp_owner)
    options = Keyword.put(options, :remote_mcp_owner, remote_owner)

    children = [
      {Task.Supervisor, name: output_tasks},
      {DynamicSupervisor, name: address(self(), :input_scope), strategy: :one_for_one},
      Supervisor.child_spec(
        {CapabilityTree, owner: Keyword.fetch!(options, :owner), name: scope_name},
        id: CapabilityTree,
        restart: :temporary,
        significant: true
      )
    ]

    children =
      if output_stt? do
        children ++
          [
            Supervisor.child_spec(
              {CapabilityTree, owner: Keyword.fetch!(options, :owner), name: output_scope_name},
              id: :output_stt_scope,
              restart: :temporary,
              significant: true
            )
          ]
      else
        children
      end

    children =
      children ++
        remote_mcp_children(options) ++
        invocation_children(options) ++
        [
          %{
            id: SpeechToSpeech,
            start: {__MODULE__, :start_capability, [scope_name, output_scope_name, options]},
            restart: :temporary,
            significant: true
          }
        ]

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end

  defp remote_mcp_children(options) do
    case Keyword.get(options, :remote_mcp) do
      nil ->
        []

      remote ->
        owner = Keyword.fetch!(options, :owner)

        remote
        |> Keyword.merge(
          activation_id: Keyword.fetch!(options, :activation_id),
          participant_id: Keyword.fetch!(options, :agent_id),
          lifecycle_owner: owner,
          initialization: {owner, Keyword.fetch!(options, :mcp_initialization_deadline)},
          initialization_mode: :deferred,
          readiness_target: owner,
          session_supervisor: address(self(), :remote_mcp_sessions),
          name: Keyword.fetch!(options, :remote_mcp_owner)
        )
        |> RemoteActivation.children()
        |> Enum.map(&Supervisor.child_spec(&1, restart: :temporary, significant: true))
    end
  end

  defp invocation_children(options) do
    activation = Keyword.get(options, :activation_id) || Id.generate(:activation)
    supervisor = address(self(), :invocation_supervisor)
    registry = address(self(), :invocation_registry)
    completions = address(self(), :tool_completions)
    limits = Keyword.get(options, :tool_invocation_options) || InvocationConfig.defaults()

    [
      {InvocationSupervisor,
       activation_id: activation,
       name: supervisor,
       maximum_children: Keyword.fetch!(limits, :maximum_tool_invocations)},
      {ToolCompletions,
       name: completions,
       registry: registry,
       owner: Keyword.fetch!(options, :owner),
       activation_id: activation},
      {InvocationRegistry,
       activation_id: activation,
       name: registry,
       invocation_supervisor: supervisor,
       completion_target: completions,
       maximum_invocations: Keyword.fetch!(limits, :maximum_tool_invocations),
       maximum_consumed_invocations: Keyword.fetch!(limits, :maximum_completed_requests),
       invocation_timeout_ms: Keyword.fetch!(limits, :tool_invocation_timeout_ms),
       maximum_result_bytes: Keyword.fetch!(limits, :maximum_tool_result_bytes)}
    ]
    |> Enum.map(&Supervisor.child_spec(&1, restart: :temporary, significant: true))
  end

  @doc false
  def start_capability(scope_name, output_scope_name, options) do
    with {:ok, remote_owner} <- resolve_mcp_owner(options),
         {:ok, private} <- PrivateInit.claim(Keyword.fetch!(options, :provider_private)),
         {:ok, output_private} <- claim_output_private(options),
         {:ok, capability} <-
           options
           |> Keyword.put(:speech_scope, CapabilityTree.scope(scope_name))
           |> Keyword.put(:provider_private, private)
           |> Keyword.put(:remote_mcp_owner, remote_owner)
           |> Keyword.put(:output_stt_private, output_private)
           |> maybe_put_output_scope(output_scope_name)
           |> SpeechToSpeech.start_link(),
         {:ok, _owner} <-
           Registry.register(
             Vxpipe.CallEngine.RoomRegistry,
             {__MODULE__, :parent, capability},
             nil
           ) do
      {:ok, capability}
    end
  end

  defp resolve_mcp_owner(options) do
    case Keyword.get(options, :remote_mcp_owner) do
      nil ->
        {:ok, nil}

      address ->
        case GenServer.whereis(address) do
          pid when is_pid(pid) -> {:ok, pid}
          nil -> {:error, :remote_owner_unavailable}
        end
    end
  end

  def start_input(capability, options) do
    DynamicSupervisor.start_child(
      address(parent(capability), :input_scope),
      {Vxpipe.CallEngine.Media.STSIngress, Keyword.put(options, :capability, capability)}
    )
  end

  defp claim_output_private(options) do
    case Keyword.fetch(options, :output_stt_private) do
      {:ok, handle} -> PrivateInit.claim(handle)
      :error -> {:ok, nil}
    end
  end

  defp maybe_put_output_scope(options, output_scope_name) do
    if Keyword.has_key?(options, :output_stt) do
      Keyword.put(options, :output_stt_scope, CapabilityTree.scope(output_scope_name))
    else
      options
    end
  end

  defp address(tree, kind) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, tree, kind}}}
  end
end
