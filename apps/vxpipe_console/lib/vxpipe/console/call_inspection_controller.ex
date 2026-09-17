defmodule Vxpipe.Console.CallInspectionController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.{CallInspectionPresenter, CallInspectionQuery}

  def show(conn, %{"call_id" => call_id}) do
    case CallInspectionQuery.run(conn.assigns.call_read_access, call_id) do
      {:ok, result} ->
        respond(conn, :ok, CallInspectionPresenter.present(result))

      {:error, :call_not_found} ->
        error(conn, :not_found, "call_not_found")

      {:error, reason}
      when reason in [:invalid_call_inspection_request, :invalid_archive_request] ->
        error(conn, :bad_request, "invalid_call_inspection")

      {:error, _reason} ->
        error(conn, :service_unavailable, "call_inspection_unavailable")
    end
  end

  defp error(conn, status, code), do: respond(conn, status, %{"error" => %{"code" => code}})

  defp respond(conn, status, body) do
    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "private, no-store")
    |> json(body)
  end
end
