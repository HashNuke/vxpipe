defmodule Vxpipe.Console.SampleTransferController do
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.{SampleAdmissionJSON, SampleCall}

  def create(conn, params) do
    case SampleCall.prepare_transfer(conn.assigns.user_principal, params) do
      {:ok, token} ->
        conn
        |> put_status(:created)
        |> json(SampleAdmissionJSON.render(token))

      {:error, :disabled} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"code" => "sample_transfer_disabled"}})

      {:error, reason} ->
        {status, code} = SampleAdmissionJSON.error_response(reason, "sample_transfer")
        conn |> put_status(status) |> json(%{error: %{code: code}})
    end
  end
end
