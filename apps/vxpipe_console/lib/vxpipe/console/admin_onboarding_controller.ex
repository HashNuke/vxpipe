defmodule Vxpipe.Console.AdminOnboardingController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator

  def ensure_demo_tenant(conn, _params) do
    case Vxpipe.Calls.ensure_demo_tenant(InstallationOperator.authority()) do
      {:ok, tenant} ->
        json(conn, %{
          tenant: %{
            key: tenant.key,
            name: tenant.name,
            created_at: DateTime.to_iso8601(tenant.inserted_at)
          }
        })

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "demo_tenant_unavailable"}})
    end
  end
end
