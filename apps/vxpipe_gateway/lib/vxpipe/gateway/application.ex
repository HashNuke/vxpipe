defmodule Vxpipe.Gateway.Application do
  @moduledoc false

  use Application

  alias Vxpipe.Gateway.{CallAdmission, CallCleanupReconciler, HTTP}
  alias Vxpipe.Gateway.SessionSupervisor
  alias Vxpipe.Gateway.Telephony.{DialSupervisor, LegSupervisor, MediaAdmission, MediaSupervisor}
  alias Vxpipe.Gateway.WebRTC.ConnectionSupervisor

  @impl true
  def start(_type, _args) do
    settings = Application.fetch_env!(:vxpipe_gateway, __MODULE__)

    Supervisor.start_link(child_specs(settings),
      strategy: :one_for_one,
      name: Vxpipe.Gateway.Supervisor
    )
  end

  @doc false
  def child_specs(settings) do
    children = [
      {Vxpipe.Gateway.MCP.Admission, Keyword.get(settings, :mcp_admission, [])},
      {Task.Supervisor, name: Vxpipe.Gateway.AdmissionTaskSupervisor},
      {Registry, keys: :unique, name: Vxpipe.Gateway.CallCleanupRegistry},
      Vxpipe.Gateway.CallCleanupSupervisor,
      {Registry, keys: :unique, name: Vxpipe.Gateway.SessionRegistry},
      SessionSupervisor,
      {Registry, keys: :unique, name: Vxpipe.Gateway.Telephony.LegRegistry},
      MediaAdmission,
      DialSupervisor,
      LegSupervisor,
      {Registry, keys: :unique, name: Vxpipe.Gateway.Media.Registry},
      MediaSupervisor,
      {Registry, keys: :unique, name: Vxpipe.Gateway.WebRTC.Registry},
      ConnectionSupervisor
    ]

    children ++ cleanup_children(settings) ++ http_children(http_options(settings))
  end

  @doc "Composes the same trusted admission configuration for standalone and embedded HTTP."
  def http_options(settings) do
    http = Keyword.fetch!(settings, :http)

    if managed_cleanup?(settings) do
      admission = Keyword.get(http, :call_admission, [])
      backend = Keyword.get(admission, :backend, {CallAdmission, []})

      {backend, shared} =
        case backend do
          {CallAdmission, options} ->
            {{CallAdmission, Keyword.put(options, :managed_cleanup, true)},
             Keyword.take(options, [:archive, :cleanup_options])}

          custom ->
            {custom, []}
        end

      http
      |> Keyword.put(:call_admission, Keyword.put(admission, :backend, backend))
      |> Keyword.update(
        :telephony,
        HTTP.TelephonyIngressConfig.with_managed_cleanup([], shared),
        &HTTP.TelephonyIngressConfig.with_managed_cleanup(&1, shared)
      )
    else
      http
    end
  end

  defp cleanup_children(settings) do
    if managed_cleanup?(settings) do
      options = settings |> Keyword.fetch!(:managed_cleanup) |> Keyword.get(:reconciler, [])
      [{CallCleanupReconciler, Keyword.put(options, :name, CallCleanupReconciler)}]
    else
      []
    end
  end

  defp managed_cleanup?(settings),
    do: settings |> Keyword.get(:managed_cleanup, []) |> Keyword.get(:enabled, false) == true

  defp http_children(http_options) do
    if Keyword.fetch!(http_options, :enabled) do
      [{HTTP.Supervisor, Keyword.delete(http_options, :enabled)}]
    else
      []
    end
  end
end
