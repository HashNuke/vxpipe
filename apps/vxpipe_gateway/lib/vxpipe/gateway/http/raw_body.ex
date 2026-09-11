defmodule Vxpipe.Gateway.HTTP.RawBody do
  @moduledoc false

  alias Plug.Conn

  @spec read(Conn.t(), pos_integer()) ::
          {:ok, binary(), Conn.t()}
          | {:error, :payload_too_large | :body_unavailable, Conn.t()}
  def read(%Conn{} = conn, maximum_bytes)
      when is_integer(maximum_bytes) and maximum_bytes > 0 do
    case Conn.read_body(conn, length: maximum_bytes, read_length: maximum_bytes) do
      {:ok, body, conn} when byte_size(body) <= maximum_bytes ->
        {:ok, body, conn}

      {:more, _partial, conn} ->
        {:error, :payload_too_large, conn}

      {:error, _reason} ->
        {:error, :body_unavailable, conn}
    end
  end
end
