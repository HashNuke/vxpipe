defmodule Vxpipe.CallEngine.Diagnostics.RoomSupervisor do
  @moduledoc "Optional room-owned observers and attachment work with an isolated restart budget."
  use Supervisor
  alias Vxpipe.CallEngine.Diagnostics.{AttachmentRunner, RoomService}

  def address(identity, role) when role in [:supervisor, :service, :workers, :runner],
    do:
      {:via, Registry,
       {Vxpipe.CallEngine.RoomRegistry,
        {:diagnostics, role, identity.tenant_id, identity.room_id, identity.incarnation_id}}}

  def options(identity, room, settings) do
    settings
    |> Keyword.validate!(
      port: Vxpipe.CallEngine.Diagnostics.SourcePort,
      source_admission: Vxpipe.CallEngine.Diagnostics.SourceAdmission,
      poll_interval_ms: 250
    )
    |> Keyword.merge(
      name: address(identity, :supervisor),
      service: address(identity, :service),
      workers: address(identity, :workers),
      runner: address(identity, :runner),
      room: room
    )
  end

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
