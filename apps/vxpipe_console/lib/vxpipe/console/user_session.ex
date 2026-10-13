defmodule Vxpipe.Console.UserSession do
  @moduledoc "Stores an opaque user-session token and resolves current authority on every request."

  alias Plug.Conn

  @session_key "vxpipe_user_session"

  @spec put(Conn.t(), String.t()) :: Conn.t()
  def put(%Conn{} = conn, token) when is_binary(token) and byte_size(token) in 32..512,
    do: Conn.put_session(conn, @session_key, token)

  def put(%Conn{} = conn, _token), do: clear(conn)

  @spec fetch(Conn.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(%Conn{} = conn, options \\ []), do: fetch_session(Conn.get_session(conn), options)

  @spec fetch_session(map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_session(session, options \\ []) do
    token = if is_map(session), do: Map.get(session, @session_key), else: nil

    if is_binary(token) and byte_size(token) in 32..512 do
      backend = Keyword.get(options, :backend, Vxpipe.Console.UserIdentity)
      backend.authenticate(token)
    else
      {:error, :invalid_session}
    end
  end

  @spec clear(Conn.t()) :: Conn.t()
  def clear(%Conn{} = conn), do: Conn.delete_session(conn, @session_key)

  @spec token(Conn.t()) :: String.t() | nil
  def token(%Conn{} = conn), do: Conn.get_session(conn, @session_key)
end
