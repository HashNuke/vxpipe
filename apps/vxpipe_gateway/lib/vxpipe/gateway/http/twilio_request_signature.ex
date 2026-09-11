defmodule Vxpipe.Gateway.HTTP.TwilioRequestSignature do
  @moduledoc false

  import Plug.Conn

  @spec fetch(Plug.Conn.t()) ::
          {:ok, String.t()} | {:error, :invalid_authentication_headers}
  def fetch(conn) do
    case get_req_header(conn, "x-twilio-signature") do
      [value] when value != "" -> {:ok, value}
      _missing_or_duplicate -> {:error, :invalid_authentication_headers}
    end
  end
end
