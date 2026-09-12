defmodule Vxpipe.Calls.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Vxpipe.Calls.PublicationSupervisor],
      strategy: :one_for_one,
      name: Vxpipe.Calls.Supervisor
    )
  end
end
