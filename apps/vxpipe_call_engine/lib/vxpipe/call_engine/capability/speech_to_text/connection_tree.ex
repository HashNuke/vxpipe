defmodule Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, PrivateInit}

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    connection_id = Keyword.fetch!(options, :connection_id)

    Supervisor.start_link(__MODULE__, options,
      name: address(incarnation_id, connection_id, :tree)
    )
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  def children(tree) do
    children = Map.new(Supervisor.which_children(tree), fn {id, pid, _, _} -> {id, pid} end)
    {:ok, Map.fetch!(children, SpeechToText), Map.fetch!(children, Ingress)}
  end

  def parent(capability) when is_pid(capability) do
    case Registry.lookup(
           Vxpipe.CallEngine.RoomRegistry,
           {__MODULE__, :parent, capability}
         ) do
      [{tree, nil}] -> tree
      [] -> nil
    end
  end

  @impl true
  def init(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    connection_id = Keyword.fetch!(options, :connection_id)
    scope_name = address(incarnation_id, connection_id, :scope)
    capability_name = address(incarnation_id, connection_id, :capability)
    capability_options = Keyword.fetch!(options, :capability_options)
    ingress_options = Keyword.fetch!(options, :ingress_options)

    children = [
      Supervisor.child_spec(
        {CapabilityTree, owner: Keyword.fetch!(options, :owner), name: scope_name},
        id: CapabilityTree,
        restart: :temporary,
        significant: true
      ),
      %{
        id: SpeechToText,
        start: {__MODULE__, :start_capability, [scope_name, capability_name, capability_options]},
        restart: :temporary,
        significant: false
      },
      %{
        id: Ingress,
        start: {__MODULE__, :start_ingress, [capability_name, ingress_options]},
        restart: :temporary,
        significant: true
      }
    ]

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end

  @doc false
  def start_capability(scope_name, capability_name, options) do
    scope = CapabilityTree.scope(scope_name)

    with {:ok, private} <- PrivateInit.claim(Keyword.fetch!(options, :provider_private)),
         {:ok, capability} <-
           options
           |> Keyword.put(:speech_scope, scope)
           |> Keyword.put(:name, capability_name)
           |> Keyword.put(:provider_private, private)
           |> SpeechToText.start_link(),
         {:ok, _owner} <-
           Registry.register(
             Vxpipe.CallEngine.RoomRegistry,
             {__MODULE__, :parent, capability},
             nil
           ) do
      {:ok, capability}
    end
  end

  @doc false
  def start_ingress(capability_name, options) do
    case GenServer.whereis(capability_name) do
      capability when is_pid(capability) ->
        Ingress.start_link(Keyword.put(options, :capability, capability))

      nil ->
        {:error, :capability_unavailable}
    end
  end

  defp address(incarnation_id, connection_id, kind) do
    {:via, Registry,
     {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, incarnation_id, connection_id, kind}}}
  end
end
