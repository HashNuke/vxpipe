defmodule Vxpipe.Gateway.WebRTC.ConnectionIncarnationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.Gateway.WebRTC.{Connection, ConnectionPeerSupervisor}

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @impl true
  def init(options) do
    connection = options |> Connection.child_spec() |> Map.put(:significant, true)

    Supervisor.init([{ConnectionPeerSupervisor, options}, connection],
      strategy: :one_for_one,
      auto_shutdown: :any_significant
    )
  end
end
