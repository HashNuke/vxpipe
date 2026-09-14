defmodule Vxpipe.Gateway.TestPreparedAudioPipeline do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options) do
    id = Keyword.fetch!(options, :pipeline_id)
    generation = id |> String.split(":") |> List.last() |> String.to_integer()

    if Keyword.get(options, :fail_generation) == generation,
      do: {:error, :test_pipeline_unavailable},
      else: GenServer.start_link(__MODULE__, options, name: via(id))
  end

  def prepare_track(id, track), do: GenServer.call(via(id), {:prepare_track, track})
  def readiness(pid) when is_pid(pid), do: GenServer.call(pid, :readiness)
  def readiness(id), do: GenServer.call(via(id), :readiness)
  def push(id, frame), do: GenServer.call(via(id), {:push, frame})
  def ready(pid), do: GenServer.call(pid, :ready)

  @impl true
  def init(options) do
    state = %{
      id: Keyword.fetch!(options, :pipeline_id),
      owner: Keyword.fetch!(options, :owner),
      observer: Keyword.fetch!(options, :test_observer),
      status: :preparing,
      track: nil,
      resource:
        Resource.new(
          :audio_input,
          {:participant, Keyword.fetch!(options, :participant_id)},
          __MODULE__,
          options,
          binding: Keyword.fetch!(options, :connection_id)
        )
    }

    send(state.observer, {:prepared_pipeline_started, self(), state.id})
    {:ok, state}
  end

  @impl true
  def handle_call({:prepare_track, track}, _from, state),
    do: {:reply, :ok, %{state | track: track}}

  def handle_call(:readiness, _from, state) do
    resource = %{
      state.resource
      | configuration: Resource.signature({state.resource.configuration, state.track})
    }

    {:reply, {:ok, resource, state.status}, state}
  end

  def handle_call(:ready, _from, state) do
    send(state.owner, {:vxpipe_audio_pipeline_ready, state.id})
    {:reply, :ok, %{state | status: :ready}}
  end

  def handle_call({:push, frame}, _from, state) do
    send(state.observer, {:prepared_pipeline_push, self(), frame})
    {:reply, :ok, state}
  end

  defp via(id),
    do: {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:test_prepared_pipeline, id}}}
end
