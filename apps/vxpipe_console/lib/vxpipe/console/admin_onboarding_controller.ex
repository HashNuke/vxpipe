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

  def install_samples(conn, _params) do
    authority = InstallationOperator.authority()

    result =
      with {:ok, tenant} <- Vxpipe.Calls.ensure_demo_tenant(authority) do
        Vxpipe.Console.DemoSamples.install(authority, tenant.key)
      end

    case result do
      {:ok, results} ->
        json(conn, %{samples: Enum.map(results, &sample_json/1)})

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
