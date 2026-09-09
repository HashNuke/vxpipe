defmodule Vxpipe.Persistence.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:vxpipe_persistence, :enabled, false) do
        [Vxpipe.Persistence.Repo]
      else
        []
      end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Persistence.Supervisor
    )
  end
end
