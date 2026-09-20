defmodule Vxpipe.CallEngine.Capability.TextToSpeech.Tree do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Output
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, PrivateInit}

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :participant_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  def capability(tree) do
    tree
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {TextToSpeech, pid, :worker, _modules} -> pid
      _child -> nil
    end)
  end

  def parent(capability) when is_pid(capability) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {__MODULE__, :parent, capability}) do
      [{tree, nil}] -> tree
      [] -> nil
    end
  end

  @impl true
  def init(options) do
    scope_name = address(self(), :scope)
    output_name = address(self(), :output)

    output_options =
      [name: output_name]
      |> maybe_put_request_timeout(options)

    children = [
      Supervisor.child_spec(
        {CapabilityTree, owner: Keyword.fetch!(options, :owner), name: scope_name},
        id: CapabilityTree,
        restart: :temporary,
        significant: true
      ),
      Supervisor.child_spec({Output, output_options},
        id: Output,
        restart: :temporary,
        significant: true
      ),
      %{
        id: TextToSpeech,
        start: {__MODULE__, :start_capability, [scope_name, output_name, options]},
        restart: :temporary,
        significant: true
      }
    ]

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end

  @doc false
  def start_capability(scope_name, output_name, options) do
    with {:ok, private} <- PrivateInit.claim(Keyword.fetch!(options, :provider_private)),
         {:ok, capability} <-
           options
           |> Keyword.put(:speech_scope, CapabilityTree.scope(scope_name))
           |> Keyword.put(:output, GenServer.whereis(output_name))
           |> Keyword.put(:provider_private, private)
           |> TextToSpeech.start_link(),
         {:ok, _owner} <-
           Registry.register(
             Vxpipe.CallEngine.RoomRegistry,
             {__MODULE__, :parent, capability},
             nil
           ) do
      {:ok, capability}
    end
  end

  defp address(tree, kind) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, tree, kind}}}
  end

  defp maybe_put_request_timeout(output_options, options) do
    case Keyword.fetch(options, :output_request_timeout) do
      {:ok, timeout} -> Keyword.put(output_options, :request_timeout, timeout)
      :error -> output_options
    end
  end
end
