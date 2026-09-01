defmodule Vxpipe.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Vxpipe.RoomRegistry},
      {Task.Supervisor, name: Vxpipe.SubscriberTaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Vxpipe.RoomsSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Vxpipe.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
