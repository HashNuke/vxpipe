defmodule Vxpipe.MCP.CheckSession do
  @moduledoc false
  use Supervisor, restart: :temporary
  alias Vxpipe.MCP.{CheckClient, CheckLifetime, CheckWorker, ConnectionNames}

  def start_link(options),
    do:
      Supervisor.start_link(__MODULE__, options,
        name: ConnectionNames.via(:owner, Keyword.fetch!(options, :key))
      )

  @impl true
  def init(options) do
    key = Keyword.fetch!(options, :key)

    children = [
      Supervisor.child_spec({CheckLifetime, options}, significant: true),
      Supervisor.child_spec({CheckClient, key}, restart: :temporary, shutdown: 100),
      %{
        id: CheckWorker,
        start: {CheckWorker, :start_link, [key]},
        restart: :temporary,
        shutdown: 100
      }
    ]

    Supervisor.init(children, strategy: :one_for_one, auto_shutdown: :any_significant)
  end
end
