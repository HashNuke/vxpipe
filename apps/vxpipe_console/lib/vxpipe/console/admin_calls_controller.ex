defmodule Vxpipe.Console.AdminCallsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Console.AdminPageParameter

  def index(conn, %{"tenant_key" => tenant_key} = params) do
    with {:ok, page} <- AdminPageParameter.parse(params),
         {:ok, definition_id} <- definition_filter(params),
         {:ok, call_page} <-
           Vxpipe.Calls.list_operator_calls(
             InstallationOperator.authority(),
             tenant_key,
             page: page,
             definition_id: definition_id
           ) do
      json(conn, %{
        tenant: %{key: call_page.tenant.key, name: call_page.tenant.name},
        definitions: Enum.map(call_page.definitions, &definition_json/1),
        definitions_truncated: call_page.definitions_truncated,
        selected_definition_id: call_page.selected_definition_id,
        calls: Enum.map(call_page.calls, &call_json/1),
        pagination: %{
          page: call_page.page,
          page_size: call_page.page_size,
          total: call_page.total,
          total_pages: call_page.total_pages
        }
      })
    else
      {:error, reason} when reason in [:tenant_not_found, :definition_not_found] ->
        conn |> put_status(404) |> json(%{error: %{code: "call_directory_not_found"}})

      {:error, :invalid_call_directory_request} ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_filter"}})

      {:error, reason} when reason in [:invalid_page, :call_page_out_of_range] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_page"}})

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "call_directory_unavailable"}})
    end
  end

  defp definition_filter(params) do
    case Map.get(params, "definition_id") do
      nil ->
        {:ok, nil}

      value when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256 ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_call_directory_request}
    end
  end

  defp definition_json(definition), do: %{id: definition.id, name: definition.name}

  defp call_json(call) do
    %{
      id: call.id,
      definition_id: call.definition_id,
      definition_name: call.definition_name,
      definition_revision: call.definition_revision,
      state: directory_state(call.state),
      created_at: DateTime.to_iso8601(call.created_at)
    }
  end

  defp directory_state(state) when state in [:prepared, :admitting, :running], do: "ongoing"
  defp directory_state(state) when state in [:ended, :failed], do: "ended"
end
