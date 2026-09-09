defmodule Vxpipe.Console.SampleCallController do
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.SampleCall

  def create(conn, _params) do
    case SampleCall.prepare() do
      {:ok, token} ->
        conn
        |> put_status(:created)
        |> json(%{
          "tenant_key" => token.tenant_key,
          "call_id" => token.call_id,
          "participant_key" => token.participant_key,
          "join_token" => %{
            "token" => token.secret,
            "expires_at" => DateTime.to_iso8601(token.expires_at)
          }
        })

      {:error, :disabled} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"code" => "durable_sample_disabled"}})

      {:error, :unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{"error" => %{"code" => "sample_call_unavailable"}})
    end
  end
end
