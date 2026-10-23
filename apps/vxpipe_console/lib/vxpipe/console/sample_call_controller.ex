defmodule Vxpipe.Console.SampleCallController do
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.{SampleAdmissionJSON, SampleCall}

  def create(conn, _params) do
    case SampleCall.prepare(conn.assigns.user_principal) do
      {:ok, token} ->
        conn
        |> put_status(:created)
        |> json(SampleAdmissionJSON.render(token))

      {:error, :disabled} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"code" => "durable_sample_disabled"}})

      {:error, reason} ->
        {status, code} = SampleAdmissionJSON.error_response(reason, "sample_call")
        conn |> put_status(status) |> json(%{error: %{code: code}})
    end
  end
end
