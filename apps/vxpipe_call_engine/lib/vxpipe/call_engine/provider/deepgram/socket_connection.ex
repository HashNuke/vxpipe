defmodule Vxpipe.CallEngine.Provider.Deepgram.SocketConnection do
  @moduledoc false

  @send_timeout 5_000

  require Mint.HTTP

  def message?(connection, message), do: Mint.HTTP.is_connection_message(connection.conn, message)

  # Headers are used only for the upgrade request. Neither successful state nor errors
  # retain the request options, URL or provider response details.
  def open(connection, options) do
    connect_timeout = Keyword.get(options, :connect_timeout, 10_000)
    receive_timeout = Keyword.get(options, :receive_timeout, 60_000)

    with {:ok, uri} <- URI.new(connection.url),
         {:ok, scheme, websocket_scheme, port} <- destination(uri),
         {:ok, conn} <-
           Mint.HTTP.connect(scheme, uri.host, port,
             protocols: [:http1],
             mode: :passive,
             log: false,
             transport_opts: [
               timeout: connect_timeout,
               send_timeout: @send_timeout,
               send_timeout_close: true
             ]
           ) do
      upgrade(conn, websocket_scheme, path(uri), connection.headers, receive_timeout)
    else
      _error -> {:error, :connection_unavailable}
    end
  rescue
    _error -> {:error, :connection_unavailable}
  end

  def send_frame(connection, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(connection.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(connection.conn, connection.ref, data) do
      {:ok, %{connection | conn: conn, websocket: websocket}}
    else
      _error -> {:error, :connection_lost}
    end
  end

  def receive_frames(connection, message) do
    case Mint.WebSocket.stream(connection.conn, message) do
      {:ok, conn, responses} -> decode_responses(%{connection | conn: conn}, responses, [])
      :unknown -> {:ok, connection, []}
      _error -> {:error, :connection_lost}
    end
  end

  def close(connection) do
    _ = Mint.HTTP.close(connection.conn)
    :ok
  end

  defp destination(%URI{scheme: "ws", host: host, port: port, userinfo: nil})
       when is_binary(host),
       do: {:ok, :http, :ws, port || 80}

  defp destination(%URI{scheme: "wss", host: host, port: port, userinfo: nil})
       when is_binary(host),
       do: {:ok, :https, :wss, port || 443}

  defp destination(_uri), do: {:error, :invalid_destination}

  defp path(uri) do
    path = if uri.path in [nil, ""], do: "/", else: uri.path
    if uri.query, do: path <> "?" <> uri.query, else: path
  end

  defp upgrade(conn, scheme, path, headers, timeout) do
    case Mint.WebSocket.upgrade(scheme, conn, path, headers) do
      {:ok, conn, ref} ->
        deadline = System.monotonic_time(:millisecond) + timeout
        await_upgrade(conn, ref, %{status: nil, headers: [], data: []}, deadline)

      {:error, conn, _reason} ->
        reject(conn)
    end
  end

  defp await_upgrade(conn, ref, response, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case Mint.HTTP.recv(conn, 0, remaining) do
      {:ok, conn, responses} ->
        finish_upgrade(conn, ref, responses, response, deadline)

      {:error, conn, _reason, _responses} ->
        reject(conn)
    end
  end

  defp finish_upgrade(conn, ref, [], response, deadline),
    do: await_upgrade(conn, ref, response, deadline)

  defp finish_upgrade(conn, ref, [{:status, ref, status} | rest], response, deadline),
    do: finish_upgrade(conn, ref, rest, %{response | status: status}, deadline)

  defp finish_upgrade(conn, ref, [{:headers, ref, headers} | rest], response, deadline),
    do:
      finish_upgrade(
        conn,
        ref,
        rest,
        %{response | headers: response.headers ++ headers},
        deadline
      )

  defp finish_upgrade(
         conn,
         ref,
         [{:data, ref, _data} = frame | rest],
         %{status: 101} = response,
         deadline
       ),
       do: finish_upgrade(conn, ref, rest, %{response | data: [frame | response.data]}, deadline)

  defp finish_upgrade(conn, ref, [{:done, ref} | _rest], response, _deadline) do
    with {:ok, conn, websocket} <-
           Mint.WebSocket.new(conn, ref, response.status, response.headers),
         {:ok, conn} <- Mint.HTTP.set_mode(conn, :active) do
      connection = %{conn: conn, ref: ref, websocket: websocket}

      case decode_responses(connection, Enum.reverse(response.data), []) do
        {:ok, connection, frames} -> {:ok, connection, frames}
        _error -> reject(conn)
      end
    else
      _error -> reject(conn)
    end
  end

  defp finish_upgrade(conn, _ref, _responses, _response, _deadline), do: reject(conn)

  defp reject(conn) do
    _ = Mint.HTTP.close(conn)
    {:error, :connection_unavailable}
  end

  defp decode_responses(connection, [], frames), do: {:ok, connection, Enum.reverse(frames)}

  defp decode_responses(connection, [{:data, ref, data} | rest], frames)
       when ref == connection.ref do
    case Mint.WebSocket.decode(connection.websocket, data) do
      {:ok, websocket, decoded} ->
        decode_responses(
          %{connection | websocket: websocket},
          rest,
          Enum.reverse(decoded, frames)
        )

      _error ->
        {:error, :connection_lost}
    end
  end

  defp decode_responses(_connection, _responses, _frames), do: {:error, :connection_lost}
end
