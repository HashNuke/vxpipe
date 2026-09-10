defmodule Vxpipe.CallEngine.AgentActivationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.AgentActivation.RuntimeGraph

  @roles [
    :coordinator,
    :invocation_registry,
    :invocation_supervisor,
    :request_supervisor,
    :session
  ]

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
    with {:ok, children} <- graph_children(options) do
      Supervisor.init(
        children,
        strategy: :one_for_all,
        max_restarts: 1,
        max_seconds: 5
      )
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp graph_children(options) do
    case Keyword.get(options, :runtime, :agent_runtime) do
      :agent_runtime -> RuntimeGraph.children(options)
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  defp via(activation_id, role) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, registry_key(activation_id, role)}}
  end

  defp registry_key(activation_id, role), do: {:agent_activation, activation_id, role}
end
