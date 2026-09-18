defmodule Vxpipe.Console.AdminCallSpecsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Console.AdminPageParameter

  def index(conn, %{"tenant_key" => tenant_key} = params) do
    with {:ok, page} <- AdminPageParameter.parse(params),
         {:ok, call_spec_page} <-
           Vxpipe.Calls.list_operator_call_specs(
             InstallationOperator.authority(),
             tenant_key,
             page: page
           ) do
      json(conn, %{
        tenant: %{key: call_spec_page.tenant.key, name: call_spec_page.tenant.name},
        call_specs: Enum.map(call_spec_page.call_specs, &call_spec_json/1),
        pagination: %{
          page: call_spec_page.page,
          page_size: call_spec_page.page_size,
          total: call_spec_page.total,
          total_pages: call_spec_page.total_pages
        }
      })
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

  defp call_spec_json(call_spec) do
    %{
      id: call_spec.id,
      name: call_spec.name,
      latest_revision: call_spec.latest_revision,
      published_revision: call_spec.published_revision,
      call_count: call_spec.call_count,
      updated_at: DateTime.to_iso8601(call_spec.updated_at)
    }
  end
end
