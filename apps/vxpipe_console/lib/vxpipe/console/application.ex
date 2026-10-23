defmodule Vxpipe.Console.Application do
  @moduledoc false

  use Application

  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Console.LiveMountLog
  alias Vxpipe.Console.RecordingConfiguration
  alias Vxpipe.Console.TelemetryReporter
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.Mount

  @impl true
  def start(_type, _args) do
    :ok = LiveMountLog.install()
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    children =
      [
        {Phoenix.PubSub, name: Vxpipe.Console.PubSub},
        {TelemetryReporter, max_pending_events: Keyword.fetch!(diagnostics, :max_pending_events)}
      ] ++ [{Endpoint, gateway_mount: gateway_mount()}]

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

    recording_settings = Application.fetch_env!(:vxpipe_console, :recording)

    recording =
      case RecordingConfiguration.build(recording_settings) do
        {:ok, recording} -> recording
        {:error, reason} -> raise ArgumentError, "invalid recording configuration: #{reason}"
      end

    gateway_settings
    |> Vxpipe.Gateway.Application.http_options()
    |> Keyword.take([
      :oauth,
      :mcp,
      :account_management,
      :tenant_directory,
      :call_spec_reads,
      :operator_api,
      :call_spec_authoring,
      :call_admission,
      :cors,
      :room_creation,
      :telephony,
      :webrtc
    ])
    |> Keyword.update(
      :oauth,
      [client_address_resolver: &Vxpipe.Console.ClientAddress.for_throttling/1],
      &Keyword.put(&1, :client_address_resolver, fn conn ->
        Vxpipe.Console.ClientAddress.for_throttling(conn)
      end)
    )
    |> Keyword.update!(:call_admission, &configure_recording(&1, recording))
    |> Keyword.update(
      :account_management,
      [browser_auth: {Vxpipe.Console.ProductAPIAuthentication, []}],
      &Keyword.put(&1, :browser_auth, {Vxpipe.Console.ProductAPIAuthentication, []})
    )
    |> Keyword.update!(:call_admission, fn options ->
      Keyword.put(options, :browser_auth, {Vxpipe.Console.ProductAPIAuthentication, []})
    end)
    |> Keyword.update!(:call_spec_authoring, fn options ->
      Keyword.put(options, :browser_auth, {Vxpipe.Console.ProductAPIAuthentication, []})
    end)
    |> Keyword.update(
      :call_spec_reads,
      [browser_auth: {Vxpipe.Console.ProductAPIAuthentication, []}],
      &Keyword.put(&1, :browser_auth, {Vxpipe.Console.ProductAPIAuthentication, []})
    )
    |> Keyword.update(
      :tenant_directory,
      [browser_auth: {Vxpipe.Console.ProductAPIAuthentication, []}],
      &Keyword.put(&1, :browser_auth, {Vxpipe.Console.ProductAPIAuthentication, []})
    )
    |> Keyword.put(:path_prefix, "/")
    |> Mount.init()
  end

  defp configure_recording(call_admission, enabled: false), do: call_admission

  defp configure_recording(call_admission, recording) do
    case Keyword.get(call_admission, :backend) do
      {CallAdmission, options} when is_list(options) ->
        Keyword.put(
          call_admission,
          :backend,
          {CallAdmission, Keyword.put(options, :recording, recording)}
        )

      _invalid ->
        raise ArgumentError, "recording requires the configured call-admission backend"
    end
  end
end
