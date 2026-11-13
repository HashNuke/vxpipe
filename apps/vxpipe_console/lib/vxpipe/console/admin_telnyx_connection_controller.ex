defmodule Vxpipe.Console.AdminTelnyxConnectionController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.OperatorTelnyxConnection
  alias Vxpipe.Gateway.HTTP.PublicOrigin
  alias Vxpipe.Providers.Telnyx.PublicEndpoint

  def show(conn, params) do
    scope = scope(params)

    respond(conn, scope, fn ->
      OperatorTelnyxConnection.get(conn.assigns.user_principal, scope)
    end)
  end

  def update(conn, params) do
    scope = scope(params)

    respond(conn, scope, fn ->
      OperatorTelnyxConnection.update(conn.assigns.user_principal, scope, conn.body_params)
    end)
  end

  defp scope(%{"tenant_key" => key}), do: key
  defp scope(_params), do: :platform

  defp respond(conn, scope, operation) do
    with {:ok, origin} <-
           PublicOrigin.current(
             Application.fetch_env!(:vxpipe_console, :service_public_origin),
             Application.get_env(:vxpipe_console, :service_public_url_provider)
           ),
         {:ok, connection} <- operation.() do
      json(
        conn,
        Map.put(connection, :webhook_urls, %{
          platform: PublicEndpoint.scoped_event_url(origin, :platform),
          tenant:
            if(is_binary(scope), do: PublicEndpoint.scoped_event_url(origin, {:tenant, scope}))
        })
      )
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp failure(conn, :forbidden), do: error(conn, 403, :forbidden)

  defp failure(conn, reason) when reason in [:tenant_not_found, :telephony_service_not_found],
    do: error(conn, 404, reason)

  defp failure(conn, reason)
       when reason in [
              :telephony_service_conflict,
              :provider_credential_conflict,
              :provider_credential_in_use,
              :phone_number_in_use
            ],
       do: error(conn, 409, reason)

  defp failure(conn, reason)
       when reason in [
              :invalid_telephony_service,
              :invalid_provider_auth,
              :invalid_tenant_key,
              :provider_credential_unavailable,
              :telnyx_application_required,
              :telephony_service_required
            ],
       do: error(conn, 422, reason)

  defp failure(conn, _reason), do: error(conn, 503, :telnyx_connection_unavailable)

  defp error(conn, status, reason),
    do: conn |> put_status(status) |> json(%{error: %{code: Atom.to_string(reason)}})
end
