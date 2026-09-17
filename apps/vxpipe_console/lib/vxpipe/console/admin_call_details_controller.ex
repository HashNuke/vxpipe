defmodule Vxpipe.Console.AdminCallDetailsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Console.{CallInspectionPresenter, CallInspectionQuery}

  def show(conn, %{"tenant_key" => tenant_key, "call_id" => call_id}) do
    authority = InstallationOperator.authority()

    with {:ok, context} <- Vxpipe.Calls.fetch_operator_call(authority, tenant_key, call_id),
         {:ok, access} <- Vxpipe.Calls.operator_call_access(authority, tenant_key),
         {:ok, result} <- CallInspectionQuery.run(access, call_id),
         true <- context.call.definition_id == result.call.definition_id,
         true <- context.call.definition_revision == result.call.definition_revision do
      respond(conn, :ok, %{
        tenant: %{key: context.tenant.key, name: context.tenant.name},
        definition: %{id: context.call.definition_id, name: context.call.definition_name},
        definition_revision: context.call.definition_revision,
        inspection: CallInspectionPresenter.present(result)
      })
    else
      {:error, reason} when reason in [:tenant_not_found, :call_not_found] ->
        error(conn, :not_found, "call_not_found")

      false ->
        error(conn, :service_unavailable, "call_inspection_unavailable")

      {:error, reason}
      when reason in [:invalid_call_inspection_request, :invalid_archive_request] ->
        error(conn, :bad_request, "invalid_call_inspection")

      {:error, _reason} ->
        error(conn, :service_unavailable, "call_inspection_unavailable")
    end
  end

  defp error(conn, status, code), do: respond(conn, status, %{error: %{code: code}})

  defp respond(conn, status, body) do
    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "private, no-store")
    |> json(body)
  end
end
