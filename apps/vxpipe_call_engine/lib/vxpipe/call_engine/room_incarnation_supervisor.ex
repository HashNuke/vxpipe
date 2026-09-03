defmodule Vxpipe.CallEngine.RoomIncarnationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.RoomAuthority

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @impl true
  def init(options) do
    authority = %{
      id: RoomAuthority,
      start: {RoomAuthority, :start_link, [options]},
      restart: :temporary,
      significant: true
    }

    Supervisor.init([authority], strategy: :one_for_one, auto_shutdown: :any_significant)
  end
end
