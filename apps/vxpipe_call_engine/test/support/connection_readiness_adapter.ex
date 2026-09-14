defmodule Vxpipe.CallEngine.TestConnectionReadinessAdapter do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Media.ConnectionReadiness

  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def negotiate(connection), do: GenServer.call(connection, :negotiate)
  def block(connection), do: GenServer.call(connection, :block)

  def replace(connection), do: GenServer.call(connection, :replace)

  def attach(connection, command, output_sink),
    do: GenServer.call(connection, {:attach, command, output_sink})

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
       readiness_block?: Keyword.get(options, :readiness_block?, false),
       readiness_waiter: nil,
       input_track: Keyword.get(options, :input_track),
       resource: resource
     }}
  end

  @impl true
  def handle_call(:vxpipe_connection_readiness, _from, binding),
    do: {:reply, {:ok, binding}, binding}

  def handle_call(:block, _from, binding), do: {:reply, :ok, %{binding | block?: true}}

  def handle_call(:negotiate, _from, binding) do
    resource = %{binding.resource | configuration: Resource.signature(:negotiated)}

    if binding.readiness_waiter do
      GenServer.reply(binding.readiness_waiter, {:ok, resource, :ready})
    end

    {:reply, :ok,
     %{
       binding
       | resource: resource,
         block?: false,
         readiness_block?: false,
         readiness_waiter: nil
     }}
  end

  def handle_call(:replace, _from, binding),
    do: {:reply, :ok, %{binding | generation: make_ref()}}

  def handle_call({:attach, command, output_sink}, _from, binding),
    do: {:reply, Vxpipe.CallEngine.attach_connection(command, output_sink), binding}

  def handle_call(:readiness, from, %{readiness_block?: true} = binding) do
    send(binding.observer, {:connection_readiness_waiting, self()})
    {:noreply, %{binding | readiness_waiter: from}}
  end

  def handle_call(:readiness, _from, binding),
    do: {:reply, {:ok, binding.resource, :ready}, binding}

  @impl true
  def handle_info({:vxpipe_event, _event}, binding), do: {:noreply, binding}

  def handle_info({:vxpipe_call_ready, _monitor}, binding) do
    send(binding.observer, {:test_call_ready, binding.identity.room_id})
    {:noreply, binding}
  end
end
