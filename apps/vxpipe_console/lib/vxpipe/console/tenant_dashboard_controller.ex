defmodule Vxpipe.Console.TenantDashboardController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.{CallDirectoryPayload, NavigationProjection}

  def show(conn, %{"tenant_key" => key}) do
    principal = conn.assigns.user_principal

    case Vxpipe.Calls.fetch_tenant_dashboard(principal, key) do
      {:ok, dashboard} ->
        response = %{tenant: NavigationProjection.tenant(principal, dashboard.tenant)}
        json(conn, with_recent_calls(response, dashboard))

      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: %{code: "dashboard_unavailable"}})
    end
  end

  defp with_recent_calls(response, %{recent_calls: %{status: :ready, calls: calls}}),
    do:
      Map.put(response, :recent_calls, %{
        status: :ready,
        calls: Enum.map(calls, &CallDirectoryPayload.call/1)
      })

  defp with_recent_calls(response, %{recent_calls: %{status: :unavailable}}),
    do: Map.put(response, :recent_calls, %{status: :unavailable})

  defp with_recent_calls(response, _dashboard), do: response
end
