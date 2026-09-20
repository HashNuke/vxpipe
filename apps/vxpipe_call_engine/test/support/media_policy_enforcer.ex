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

  def request_and_stop(enforcer, server, request, reply_to, tag),
    do: GenServer.cast(enforcer, {:request_and_stop, server, request, reply_to, tag})

  @impl true
  def init(options) do
    Process.flag(:trap_exit, Keyword.get(options, :trap_exit, false))

    {:ok,
     %{
       last_revision: nil,
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

  def handle_call(
        {:vxpipe_apply_media_policy, snapshot},
        _from,
        %{mode: :monotonic, last_revision: revision} = state
      ) do
    send(state.owner, {:media_policy_applied, self(), snapshot})

    if revision == nil or snapshot.revision > revision,
      do: {:reply, :ok, %{state | last_revision: snapshot.revision}},
      else: {:reply, {:error, :stale_policy_revision}, state}
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

  def handle_cast({:request_and_stop, server, request, reply_to, tag}, state) do
    send(server, {:"$gen_call", {reply_to, tag}, request})
    {:stop, :normal, state}
  end
end
