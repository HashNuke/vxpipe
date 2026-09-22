defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree do
  @moduledoc "Agent-owned temporary subtree for one speech-to-speech allocation."

  use Supervisor

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, PrivateInit}

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :agent_id)},
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
      {SpeechToSpeech, pid, :worker, _modules} -> pid
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
    output_scope_name = address(self(), :output_stt_scope)
    output_stt? = Keyword.has_key?(options, :output_stt)

    children = [
      {DynamicSupervisor, name: address(self(), :input_scope), strategy: :one_for_one},
      Supervisor.child_spec(
        {CapabilityTree, owner: Keyword.fetch!(options, :owner), name: scope_name},
        id: CapabilityTree,
        restart: :temporary,
        significant: true
      )
    ]

    children =
      if output_stt? do
        children ++
          [
            Supervisor.child_spec(
              {CapabilityTree, owner: Keyword.fetch!(options, :owner), name: output_scope_name},
              id: :output_stt_scope,
              restart: :temporary,
              significant: true
            )
          ]
      else
        children
      end

    children =
      children ++
        [
          %{
            id: SpeechToSpeech,
            start: {__MODULE__, :start_capability, [scope_name, output_scope_name, options]},
            restart: :temporary,
            significant: true
          }
        ]

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end

  @doc false
  def start_capability(scope_name, output_scope_name, options) do
    with {:ok, private} <- PrivateInit.claim(Keyword.fetch!(options, :provider_private)),
         {:ok, output_private} <- claim_output_private(options),
         {:ok, capability} <-
           options
           |> Keyword.put(:speech_scope, CapabilityTree.scope(scope_name))
           |> Keyword.put(:provider_private, private)
           |> Keyword.put(:output_stt_private, output_private)
           |> maybe_put_output_scope(output_scope_name)
           |> SpeechToSpeech.start_link(),
         {:ok, _owner} <-
           Registry.register(
             Vxpipe.CallEngine.RoomRegistry,
             {__MODULE__, :parent, capability},
             nil
           ) do
      {:ok, capability}
    end
  end

  def start_input(capability, options) do
    DynamicSupervisor.start_child(
      address(parent(capability), :input_scope),
      {Vxpipe.CallEngine.Media.STSIngress, Keyword.put(options, :capability, capability)}
    )
  end

  defp claim_output_private(options) do
    case Keyword.fetch(options, :output_stt_private) do
      {:ok, handle} -> PrivateInit.claim(handle)
      :error -> {:ok, nil}
    end
  end

  defp maybe_put_output_scope(options, output_scope_name) do
    if Keyword.has_key?(options, :output_stt) do
      Keyword.put(options, :output_stt_scope, CapabilityTree.scope(output_scope_name))
    else
      options
    end
  end

  defp address(tree, kind) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, tree, kind}}}
  end
end
