defmodule Vxpipe.CallEngine.TestRecordingOutput do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def readiness(pid), do: GenServer.call(pid, :readiness)
  def bind(pid, handoff), do: GenServer.call(pid, {:bind, handoff})
  def pause_binding(pid), do: GenServer.call(pid, :pause_binding)

  def recording_binding(pid) do
    case GenServer.call(pid, :recording_binding) do
      {:pause, observer, reply} ->
        send(observer, {:recording_binding_paused, self()})

        receive do
          :continue -> reply
        end

      reply ->
        reply
    end
  end

  @impl true
  def init(options) do
    {:ok,
     %{
       observer: Keyword.fetch!(options, :observer),
       handoff: nil,
       pause?: false,
       resource:
         Resource.new(:audio_output, {:participant, "caller"}, __MODULE__, options,
           binding: "listener-connection"
         )
     }}
  end

  @impl true
  def handle_call(:readiness, _from, state), do: {:reply, {:ok, state.resource, :ready}, state}

  def handle_call({:bind, handoff}, _from, state),
    do: {:reply, :ok, %{state | handoff: handoff}}

  def handle_call(:pause_binding, _from, state), do: {:reply, :ok, %{state | pause?: true}}

  def handle_call(:recording_binding, _from, state) do
    reply =
      if state.handoff,
        do:
          {:ok, state.resource, state.handoff,
           %{sample_rate: 48_000, channels: 1, frame_samples: 960}},
        else: {:error, :recording_not_bound}

    reply = if state.pause?, do: {:pause, state.observer, reply}, else: reply
    {:reply, reply, %{state | pause?: false}}
  end
end
