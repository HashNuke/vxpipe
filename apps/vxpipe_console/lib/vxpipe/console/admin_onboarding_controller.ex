defmodule Vxpipe.Console.AdminOnboardingController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  def ensure_demo_tenant(conn, _params) do
    case Vxpipe.Calls.ensure_demo_tenant(conn.assigns.user_principal) do
      {:ok, tenant} ->
        json(conn, %{
          tenant: %{
            key: tenant.key,
            name: tenant.name,
            created_at: DateTime.to_iso8601(tenant.inserted_at)
          }
        })

      {:error, :forbidden} ->
        conn
        |> put_status(403)
        |> json(%{error: %{code: "forbidden"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "demo_tenant_unavailable"}})
    end
  end

  def install_samples(conn, params) do
    result = Vxpipe.Calls.install_demo_samples(conn.assigns.user_principal, params["tenant_key"])

    case result do
      {:ok, results} ->
        json(conn, %{samples: Enum.map(results, &sample_json/1)})

      {:error, :forbidden} ->
        conn
        |> put_status(403)
        |> json(%{error: %{code: "forbidden"}})

      {:error, :invalid_tenant_key} ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_tenant_key"}})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "demo_tenant_not_found"}})

      {:error, :sample_prerequisites_missing} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "sample_prerequisites_missing"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "sample_installation_unavailable"}})
    end
  end

  defp sample_json(sample) do
    %{
      id: sample.id,
      name: sample.name,
      status: Atom.to_string(sample.status)
    }
    |> maybe_put_revision(sample)
  end

  defp maybe_put_revision(json, %{revision: revision}), do: Map.put(json, :revision, revision)
  defp maybe_put_revision(json, _sample), do: json
end
