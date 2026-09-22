defmodule Vxpipe.CallEngine.TestSTSRejectingPolicyAuthority do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options), do: {:ok, Map.new(options)}

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:register_enforcer, capability, _connection}, _from, state) do
    send(state.observer, {:sts_policy_registration_rejected, capability, Tree.parent(capability)})
    {:reply, {:error, :enforcement_failed}, state}
  end

  def handle_call({:retire_connection_enforcers, _connection, _enforcers}, _from, state),
    do: {:reply, :ok, state}
end
