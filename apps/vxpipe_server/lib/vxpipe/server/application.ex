defmodule Vxpipe.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [http_server_child_spec()]

    opts = [strategy: :one_for_one, name: Vxpipe.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp http_server_child_spec do
    config = Application.fetch_env!(:vxpipe_server, :http)

    Supervisor.child_spec(
      {Bandit,
       plug: Vxpipe.Web.Router,
       ip: Keyword.fetch!(config, :ip),
       port: Keyword.fetch!(config, :port),
       startup_log: Keyword.get(config, :startup_log, :info)},
      id: Vxpipe.Server.HTTP
    )
  end
end
