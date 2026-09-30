defmodule Vxpipe.CallEngine.TestTTSHTTPServer do
  @moduledoc false
  @behaviour Plug

  def child_spec(options) do
    Supervisor.child_spec(
      {Bandit, plug: {__MODULE__, options}, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
      id: {__MODULE__, make_ref()}
    )
  end

  def endpoint(server) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}/tts/bytes"
  end

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, options) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    owner = Keyword.fetch!(options, :owner)

    send(
      owner,
      {:tts_http_request, self(), conn.request_path,
       Plug.Conn.get_req_header(conn, "authorization"), JSON.decode!(body)}
    )

    conn =
      Plug.Conn.put_resp_header(conn, "content-type", Keyword.get(options, :type, "audio/pcm"))

    if Keyword.get(options, :status, 200) == 302 do
      conn |> Plug.Conn.put_resp_header("location", "/redirected") |> Plug.Conn.send_resp(302, "")
    else
      conn = Plug.Conn.send_chunked(conn, Keyword.get(options, :status, 200))

      Enum.reduce(Keyword.get(options, :chunks, [<<1, 0, 2, 0>>]), conn, fn chunk, current ->
        {:ok, next} = Plug.Conn.chunk(current, chunk)
        next
      end)
    end
  end
end
