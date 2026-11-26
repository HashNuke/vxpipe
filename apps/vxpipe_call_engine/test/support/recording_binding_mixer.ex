defmodule Vxpipe.CallEngine.TestRecordingBindingMixer do
  use GenServer

  alias Vxpipe.CallEngine.Recording.EgressHandoff

  def start_link(state), do: GenServer.start_link(__MODULE__, state)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:open_recording_egress, _id}, _from, :unavailable),
    do: {:reply, {:error, :unavailable}, :unavailable}

  def handle_call({:open_recording_egress, _id, _listener}, _from, :unavailable),
    do: {:reply, {:error, :unavailable}, :unavailable}

  def handle_call(
        {:open_recording_egress, id},
        _from,
        {observer, identity, config, counters} = state
      ) do
    send(observer, {:mixer_open_requested, id})
    handoff = EgressHandoff.new(observer, make_ref(), identity, config, id, 10, counters)
    {:reply, {:ok, handoff}, state}
  end

  def handle_call(
        {:open_recording_egress, id, _listener},
        _from,
        {observer, identity, config, counters} = state
      ) do
    send(observer, {:mixer_open_requested, id})
    handoff = EgressHandoff.new(observer, make_ref(), identity, config, id, 10, counters)
    {:reply, {:ok, handoff}, state}
  end
end
