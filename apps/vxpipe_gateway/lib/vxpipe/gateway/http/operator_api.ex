defmodule Vxpipe.Gateway.HTTP.OperatorAPI do
  @moduledoc false
  import Plug.Conn

  def init(options),
    do: %{
      enabled: Keyword.get(options, :enabled, false),
      calls: Keyword.delete(options, :enabled)
    }

  def status(conn, %{enabled: false}), do: send_resp(conn, 404, "not found")

  def status(conn, %{calls: options}) do
    with ["Bearer " <> secret] <- get_req_header(conn, "authorization"),
         {:ok, authority} <- Vxpipe.Calls.authenticate_operator(secret, options) do
      json(conn, 200, %{authority: "installation_operator", api_key_id: authority.api_key_id})
    else
      {:error, :invalid_api_key} ->
        json(conn, 401, %{error: %{code: "invalid_api_key"}})

      {:error, _reason} ->
        json(conn, 503, %{error: %{code: "operator_authentication_unavailable"}})

      _missing ->
        json(conn, 401, %{error: %{code: "invalid_api_key"}})
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
