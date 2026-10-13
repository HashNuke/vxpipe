defmodule Vxpipe.Console.AdminPhoneNumbersController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls.{CallSpecErrors, OperatorPhoneNumbers}

  def index(conn, %{"tenant_key" => tenant, "service" => service} = params) do
    query = %{
      search: Map.get(params, "search", ""),
      page: Map.get(params, "page"),
      call_spec_id: Map.get(params, "call_spec_id")
    }

    request_options = Application.get_env(:vxpipe_console, :phone_number_request_options, [])

    reader = fn snapshot, query ->
      service = snapshot.service

      Vxpipe.Gateway.PhoneNumberCatalog.list(
        service.provider,
        service.provider_connection_id,
        snapshot.credential.payload,
        query.search,
        query.page,
        request_options
      )
    end

    case OperatorPhoneNumbers.list(conn.assigns.user_principal, tenant, service, query,
           number_reader: reader
         ) do
      {:ok, page} ->
        json(conn, page)

      {:error, reason} ->
        {status, error} = CallSpecErrors.response(reason)
        conn |> put_status(status) |> json(%{error: error})
    end
  rescue
    _ -> conn |> put_status(503) |> json(%{error: %{code: "phone_numbers_unavailable"}})
  end
end
