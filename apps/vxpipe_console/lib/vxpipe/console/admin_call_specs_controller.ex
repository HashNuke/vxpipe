defmodule Vxpipe.Console.AdminCallSpecsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.AdminPageParameter

  def index(conn, %{"tenant_key" => tenant_key} = params) do
    with {:ok, page} <- AdminPageParameter.parse(params),
         {:ok, call_spec_page} <-
           Vxpipe.Calls.list_operator_call_specs(
             conn.assigns.user_principal,
             tenant_key,
             page: page
           ) do
      json(conn, Vxpipe.Gateway.CallSpecJSON.page(call_spec_page))
    else
      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, reason} when reason in [:invalid_page, :call_spec_page_out_of_range] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_page"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "call_spec_directory_unavailable"}})
    end
  end
end
