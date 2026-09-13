defmodule Vxpipe.CallEngine.TestConnectionReadinessAdapter do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Media.ConnectionReadiness

  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def replace(connection), do: GenServer.call(connection, :replace)
  def attach(connection, command), do: GenServer.call(connection, {:attach, command})
  def readiness(connection), do: GenServer.call(connection, :readiness)

  @impl true
  def prepare_binding(binding, policy, demand) do
    send(binding.observer, {:connection_preparation_started, self(), policy, demand})

    if binding.block? do
      send(binding.observer, {:connection_preparation_waiting, self(), binding.identity})

      receive do
        :continue -> :ok
      end
    end

    track = if demand.audio_input? or demand.speech_to_text?, do: binding.input_track
    {:ok, [binding.resource], track}
  end

  @impl true
  def init(options) do
    identity = Keyword.fetch!(options, :identity)

    resource =
      Resource.new(
        :media_connection,
        {:participant, identity.participant_id},
        __MODULE__,
        identity,
        binding: identity.connection_id
      )

    resource = Keyword.get(options, :resource, resource)

    {:ok,
     %{
       identity: identity,
       instance: self(),
       generation: make_ref(),
       adapter: Keyword.get(options, :adapter, __MODULE__),
       observer: Keyword.fetch!(options, :observer),
       block?: Keyword.get(options, :block?, false),
       input_track: Keyword.get(options, :input_track),
       resource: resource
     }}
  end

  @impl true
  def handle_call(:vxpipe_connection_readiness, _from, binding),
    do: {:reply, {:ok, binding}, binding}

  def handle_call(:replace, _from, binding),
    do: {:reply, :ok, %{binding | generation: make_ref()}}

  def handle_call({:attach, command}, _from, binding),
    do: {:reply, Vxpipe.CallEngine.attach_connection(command), binding}

  def handle_call(:readiness, _from, binding),
    do: {:reply, {:ok, binding.resource, :ready}, binding}

  @impl true
  def handle_info({:vxpipe_event, _event}, binding), do: {:noreply, binding}
end
