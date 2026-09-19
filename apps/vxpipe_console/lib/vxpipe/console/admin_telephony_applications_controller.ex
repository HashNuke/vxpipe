defmodule Vxpipe.Console.AdminTelephonyApplicationsController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.{InstallationOperator, OperatorTelephonyApplications}

  def index(conn, %{"tenant_key" => tenant}) do
    case OperatorTelephonyApplications.list(InstallationOperator.authority(), tenant) do
      {:ok, directory} -> json(conn, directory)
      {:error, reason} -> failure(conn, reason)
    end
  end

  def create(conn, %{"tenant_key" => tenant}) do
    case OperatorTelephonyApplications.create(
           InstallationOperator.authority(),
           tenant,
           conn.body_params
         ) do
      {:ok, application} -> conn |> put_status(201) |> json(%{application: application})
      {:error, reason} -> failure(conn, reason)
    end
  end

  def update(conn, %{"tenant_key" => tenant, "service_id" => id}) do
    case OperatorTelephonyApplications.update(
           InstallationOperator.authority(),
           tenant,
           id,
           conn.body_params
         ) do
      {:ok, application} -> json(conn, %{application: application})
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp failure(conn, reason) when reason in [:tenant_not_found, :telephony_service_not_found],
    do: conn |> put_status(404) |> json(%{error: %{code: Atom.to_string(reason)}})

  defp failure(conn, :telephony_service_conflict),
    do: conn |> put_status(409) |> json(%{error: %{code: "telephony_service_conflict"}})

  defp failure(conn, reason)
       when reason in [
              :invalid_telephony_service,
              :invalid_tenant_key,
              :provider_credential_unavailable
            ],
       do: conn |> put_status(422) |> json(%{error: %{code: Atom.to_string(reason)}})

  defp failure(conn, _reason),
    do: conn |> put_status(503) |> json(%{error: %{code: "telephony_services_unavailable"}})
end
