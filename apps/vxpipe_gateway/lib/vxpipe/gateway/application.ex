defmodule Vxpipe.Gateway.Application do
  @moduledoc false

  use Application

  alias Vxpipe.Gateway.HTTP
  alias Vxpipe.Gateway.SessionSupervisor
  alias Vxpipe.Gateway.Telephony.{LegSupervisor, MediaAdmission}
  alias Vxpipe.Gateway.WebRTC.ConnectionSupervisor

  @impl true
  def start(_type, _args) do
    settings = Application.fetch_env!(:vxpipe_gateway, __MODULE__)

    children = [
      {Task.Supervisor, name: Vxpipe.Gateway.AdmissionTaskSupervisor},
      {Registry, keys: :unique, name: Vxpipe.Gateway.SessionRegistry},
      SessionSupervisor,
      {Registry, keys: :unique, name: Vxpipe.Gateway.Telephony.LegRegistry},
      MediaAdmission,
      LegSupervisor,
      {Registry, keys: :unique, name: Vxpipe.Gateway.Media.Registry},
      {Registry, keys: :unique, name: Vxpipe.Gateway.WebRTC.Registry},
      ConnectionSupervisor
    ]

    children = children ++ http_children(Keyword.fetch!(settings, :http))

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Gateway.Supervisor
    )
  end

  defp http_children(http_options) do
    if Keyword.fetch!(http_options, :enabled) do
      [{HTTP.Supervisor, Keyword.delete(http_options, :enabled)}]
    else
      []
    end
  end
end
