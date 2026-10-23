defmodule Vxpipe.Gateway.HTTP.ProductAuthentication do
  @moduledoc "Selects one configured product API credential without merging session and key grants."

  import Plug.Conn

  def authenticate(conn, browser_auth, authenticate_key) do
    case {get_req_header(conn, "authorization"), browser_auth} do
      {[], {module, context}} ->
        module.authenticate(conn, context)

      _key_request ->
        with {:ok, secret} <- bearer(conn),
             {:ok, actor} <- authenticate_key.(secret) do
          {:ok, conn, actor}
        end
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> secret] when byte_size(secret) in 1..256 -> {:ok, secret}
      _invalid -> {:error, :invalid_api_key}
    end
  end
end
