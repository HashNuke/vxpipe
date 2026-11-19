defmodule Vxpipe.CallEngine.Diagnostics.RoomSupervisor do
  @moduledoc "Optional room-owned observers and attachment work with an isolated restart budget."
  use Supervisor
  alias Vxpipe.CallEngine.Diagnostics.{AttachmentRunner, RoomService}

  def child_spec(options),
    do: %{
      id: {__MODULE__, Keyword.fetch!(options, :name)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      significant: false,
      shutdown: :infinity,
      type: :supervisor
    }

  def start_link(options),
    do: Supervisor.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  @impl true
  def init(options) do
    children = [
      {DynamicSupervisor,
       name: Keyword.fetch!(options, :workers), strategy: :one_for_one, max_children: 32},
      {AttachmentRunner, name: Keyword.fetch!(options, :runner)},
      {RoomService, Keyword.delete(options, :name)}
    ]

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 2, max_seconds: 5)
  end
end
