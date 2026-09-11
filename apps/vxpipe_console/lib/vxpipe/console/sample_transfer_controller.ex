defmodule Vxpipe.Console.SampleTransferController do
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.{SampleAdmissionJSON, SampleCall}

  def create(conn, _params) do
    case SampleCall.prepare_transfer() do
      {:ok, token} ->
        conn
        |> put_status(:created)
        |> json(SampleAdmissionJSON.render(token))

      {:error, :call_not_prepared} ->
        conn
        |> put_status(:conflict)
        |> json(%{"error" => %{"code" => "sample_call_not_prepared"}})

      {:error, :disabled} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"code" => "sample_transfer_disabled"}})

      {:error, :unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{"error" => %{"code" => "sample_transfer_unavailable"}})
    end
  end
end
