defmodule Vxpipe.CallEngine.TestConnectionReadinessAdapter do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Media.ConnectionReadiness

  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def replace(connection), do: GenServer.call(connection, :replace)

  @impl true
  def prepare_binding(binding, policy, demand) do
    send(binding.observer, {:connection_preparation_started, self(), policy, demand})

    if binding.block? do
      receive do
        :continue -> :ok
      end
    end

    {:ok, [binding.resource], nil}
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
       resource: resource
     }}
  end

  @impl true
  def handle_call(:vxpipe_connection_readiness, _from, binding),
    do: {:reply, {:ok, binding}, binding}

  def handle_call(:replace, _from, binding),
    do: {:reply, :ok, %{binding | generation: make_ref()}}
end
