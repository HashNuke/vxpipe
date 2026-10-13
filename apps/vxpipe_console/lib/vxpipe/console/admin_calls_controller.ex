defmodule Vxpipe.Console.AdminCallsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.AdminPageParameter

  def index(conn, %{"tenant_key" => tenant_key} = params) do
    with {:ok, page} <- AdminPageParameter.parse(params),
         {:ok, call_spec_id} <- call_spec_filter(params),
         {:ok, call_page} <-
           Vxpipe.Calls.list_operator_calls(
             conn.assigns.user_principal,
             tenant_key,
             page: page,
             call_spec_id: call_spec_id
           ) do
      json(conn, %{
        tenant: %{key: call_page.tenant.key, name: call_page.tenant.name},
        call_specs: Enum.map(call_page.call_specs, &call_spec_json/1),
        call_specs_truncated: call_page.call_specs_truncated,
        selected_call_spec_id: call_page.selected_call_spec_id,
        calls: Enum.map(call_page.calls, &Vxpipe.Console.CallDirectoryPayload.call/1),
        pagination: %{
          page: call_page.page,
          page_size: call_page.page_size,
          total: call_page.total,
          total_pages: call_page.total_pages
        }
      })
    else
      {:error, reason} when reason in [:tenant_not_found, :call_spec_not_found] ->
        conn |> put_status(404) |> json(%{error: %{code: "call_directory_not_found"}})

      {:error, :invalid_call_directory_request} ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_filter"}})

      {:error, reason} when reason in [:invalid_page, :call_page_out_of_range] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_page"}})

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "call_directory_unavailable"}})
    end
  end

  defp call_spec_filter(params) do
    case Map.get(params, "call_spec_id") do
      nil ->
        {:ok, nil}

      value when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256 ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_call_directory_request}
    end
  end

  defp call_spec_json(call_spec), do: %{id: call_spec.id, name: call_spec.name}
end
