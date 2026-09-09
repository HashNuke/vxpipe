defmodule Vxpipe.Console.Application do
  @moduledoc false

  use Application

  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Console.TelemetryReporter
  alias Vxpipe.Gateway.HTTP.Mount

  @impl true
  def start(_type, _args) do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    children = [
      {Phoenix.PubSub, name: Vxpipe.Console.PubSub},
      {TelemetryReporter, max_pending_events: Keyword.fetch!(diagnostics, :max_pending_events)},
      {Endpoint, gateway_mount: gateway_mount()}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Console.Supervisor
    )
  end

  @impl true
  def config_change(changed, removed, _extra) do
    Endpoint.config_change(changed, removed)
    :ok
  end

  defp gateway_mount do
    gateway_settings =
      Application.fetch_env!(:vxpipe_gateway, Vxpipe.Gateway.Application)

    gateway_settings
    |> Keyword.fetch!(:http)
    |> Keyword.take([:call_admission, :cors, :room_creation, :webrtc])
    |> Keyword.put(:path_prefix, "/")
    |> Mount.init()
  end
end
