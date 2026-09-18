defmodule Vxpipe.Console.AdminDefinitionsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Console.AdminPageParameter

  def index(conn, %{"tenant_key" => tenant_key} = params) do
    with {:ok, page} <- AdminPageParameter.parse(params),
         {:ok, definition_page} <-
           Vxpipe.Calls.list_operator_definitions(
             InstallationOperator.authority(),
             tenant_key,
             page: page
           ) do
      json(conn, %{
        tenant: %{key: definition_page.tenant.key, name: definition_page.tenant.name},
        definitions: Enum.map(definition_page.definitions, &definition_json/1),
        pagination: %{
          page: definition_page.page,
          page_size: definition_page.page_size,
          total: definition_page.total,
          total_pages: definition_page.total_pages
        }
      })
    else
      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, reason} when reason in [:invalid_page, :definition_page_out_of_range] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_page"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "definition_directory_unavailable"}})
    end
  end

  defp definition_json(definition) do
    %{
      id: definition.id,
      name: definition.name,
      latest_revision: definition.latest_revision,
      published_revision: definition.published_revision,
      call_count: definition.call_count,
      updated_at: DateTime.to_iso8601(definition.updated_at)
    }
  end
end
