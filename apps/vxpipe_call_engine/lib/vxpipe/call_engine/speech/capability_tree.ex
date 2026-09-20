defmodule Vxpipe.CallEngine.Speech.CapabilityTree do
  @moduledoc "Temporary local ownership for a live speech allocation and its prepared replacement."
  use Supervisor

  alias Vxpipe.CallEngine.Speech.{Admission, Scope, ScopeControl}

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [Keyword.put_new(options, :owner, self())]},
      type: :supervisor,
      restart: :temporary,
      shutdown: :infinity
    }
  end

  def start_link(options) do
    name = Keyword.get(options, :name, address({:capability, make_ref()}))
    Supervisor.start_link(__MODULE__, options, name: name)
  end

  def scope(tree) do
    children = Map.new(Supervisor.which_children(tree), fn {id, pid, _, _} -> {id, pid} end)

    %Scope{
      tree: tree,
      control: Map.fetch!(children, ScopeControl),
      sessions: Map.fetch!(children, :sessions),
      admissions: Map.fetch!(children, :admissions)
    }
  end

  @doc false
  def address(key), do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, key}}}

  @impl true
  def init(options) do
    children = [
      {ScopeControl, owner: Keyword.fetch!(options, :owner)},
      Supervisor.child_spec({Admission, name: address({self(), :admissions})},
        id: :admissions,
        shutdown: :brutal_kill
      ),
      Supervisor.child_spec(
        {DynamicSupervisor, name: address({self(), :sessions}), strategy: :one_for_one},
        id: :sessions
      )
    ]

    children =
      Enum.map(children, &Supervisor.child_spec(&1, restart: :temporary, significant: true))

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end
end
