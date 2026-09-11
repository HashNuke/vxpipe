defmodule Vxpipe.Gateway.Telephony.MediaConnectionSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.Gateway.Telephony.{MediaChildrenSupervisor, MediaSession}

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    Supervisor.start_link(__MODULE__, options, name: via(connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :supervisor
    }
  end

  @impl true
  def init(options) do
    connection_id = Keyword.fetch!(options, :connection_id)

    children = [
      {MediaChildrenSupervisor, connection_id: connection_id},
      Supervisor.child_spec({MediaSession, options}, restart: :temporary, significant: true)
    ]

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end

  defp via(connection_id) do
    {:via, Registry,
     {Vxpipe.Gateway.Media.Registry, {:telephony_media_connection, connection_id}}}
  end
end
