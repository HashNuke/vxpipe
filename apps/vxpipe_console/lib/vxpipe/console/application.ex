defmodule Vxpipe.Console.Application do
  @moduledoc false

  use Application

  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Console.RecordingConfiguration
  alias Vxpipe.Console.SampleCall
  alias Vxpipe.Console.TelemetryReporter
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.Mount

  @impl true
  def start(_type, _args) do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)
    sample_call = Application.fetch_env!(:vxpipe_console, :sample_call)

    children =
      [
        {Phoenix.PubSub, name: Vxpipe.Console.PubSub},
        {TelemetryReporter, max_pending_events: Keyword.fetch!(diagnostics, :max_pending_events)}
      ] ++ sample_call_children(sample_call) ++ [{Endpoint, gateway_mount: gateway_mount()}]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Console.Supervisor
    )
  end

  defp sample_call_children(settings) do
    if Keyword.get(settings, :enabled, false) do
      [{SampleCall, Keyword.delete(settings, :enabled)}]
    else
      []
    end
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
    |> Keyword.fetch!(:http)
    |> Keyword.take([
      :operator_api,
      :call_spec_authoring,
      :call_admission,
      :cors,
      :room_creation,
      :telephony,
      :webrtc
    ])
    |> Keyword.update!(:call_admission, &configure_recording(&1, recording))
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
