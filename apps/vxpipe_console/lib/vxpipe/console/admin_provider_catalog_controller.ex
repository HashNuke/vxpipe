defmodule Vxpipe.Console.AdminProviderCatalogController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls.{ProviderCatalogErrors}

  def index(conn, %{"tenant_key" => tenant} = params) do
    Vxpipe.Calls.list_providers(
      conn.assigns.user_principal,
      tenant,
      Map.get(params, "capability")
    )
    |> respond(conn)
  end

  def models(conn, %{"tenant_key" => tenant, "provider" => provider} = params) do
    Vxpipe.Calls.list_provider_models(
      conn.assigns.user_principal,
      tenant,
      provider,
      Map.get(params, "capability")
    )
    |> respond(conn)
  end

  defp respond({:ok, result}, conn),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(result)

  defp respond({:error, reason}, conn) do
    {status, error} = ProviderCatalogErrors.response(reason)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: error})
  end
end
