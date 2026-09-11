defmodule Vxpipe.CallEngine.TestMediaPolicyEnforcer do
  @moduledoc false

  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def acknowledge(enforcer, outcome), do: GenServer.cast(enforcer, {:acknowledge, outcome})

  @impl true
  def init(options) do
    {:ok,
     %{
       mode: Keyword.get(options, :mode, :automatic),
       owner: Keyword.fetch!(options, :owner),
       pending: nil
     }}
  end

  @impl true
  def handle_call({:vxpipe_apply_media_policy, snapshot}, from, %{mode: :manual} = state) do
    send(state.owner, {:media_policy_applied, self(), snapshot})
    {:noreply, %{state | pending: from}}
  end

  def handle_call({:vxpipe_apply_media_policy, snapshot}, _from, state) do
    send(state.owner, {:media_policy_applied, self(), snapshot})
    {:reply, state.mode, state}
  end

  @impl true
  def handle_cast({:acknowledge, outcome}, %{pending: pending} = state) when pending != nil do
    GenServer.reply(pending, outcome)
    {:noreply, %{state | pending: nil}}
  end
end
