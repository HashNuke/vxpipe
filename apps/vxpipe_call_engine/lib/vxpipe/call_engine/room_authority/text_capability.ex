defmodule Vxpipe.CallEngine.RoomAuthority.TextCapability do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator, as: AgentRuntimeCoordinator
  alias Vxpipe.CallEngine.RoomAuthority.State

  @spec ready?(State.t()) :: boolean()
  def ready?(%State{text_capability: nil}), do: false

  def ready?(%State{} = state) do
    MapSet.member?(state.participant_ids, state.text_capability.participant_id)
  end

  @spec current?(State.t(), pid()) :: boolean()
  def current?(%State{text_capability: nil}, _capability), do: false

  def current?(%State{} = state, capability) do
    GenServer.whereis(state.text_capability.pid) == capability
  rescue
    _exception -> false
  end

  @spec respond(map(), struct()) :: :ok | {:error, term()}
  def respond(%{module: module, pid: capability}, command) do
    module.respond(capability, command)
  end

  @spec fixed_greeting(map(), struct(), String.t()) :: :ok | {:error, term()}
  def fixed_greeting(%{module: AgentRuntimeCoordinator, pid: capability}, command, text) do
    AgentRuntimeCoordinator.fixed_greeting(capability, command, text)
  end

  @spec generated_greeting(map(), struct()) :: :ok | {:error, term()}
  def generated_greeting(%{module: AgentRuntimeCoordinator, pid: capability}, command) do
    AgentRuntimeCoordinator.generated_greeting(capability, command)
  end

  @spec caller_idle(map(), struct()) :: :ok | {:error, term()}
  def caller_idle(%{module: AgentRuntimeCoordinator, pid: capability}, command) do
    AgentRuntimeCoordinator.caller_idle(capability, command)
  end

  def caller_idle(_capability, _command), do: {:error, :unavailable}

  @spec stop(State.t()) :: :ok | {:error, term()}
  def stop(%State{text_capability: %{module: AgentRuntimeCoordinator}}), do: :ok

  def stop(%State{} = state) do
    Vxpipe.CallEngine.RoomCapabilitySupervisor.stop_capability(
      state.snapshot.incarnation_id,
      state.text_capability.pid
    )
  end
end
