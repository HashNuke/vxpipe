defmodule Vxpipe.CallEngine.TestSpeechWireServer do
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
    "ws://127.0.0.1:#{port}/speech"
  end

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, options) do
    owner = Keyword.fetch!(options, :owner)
    send(owner, {:speech_wire_authorization, Plug.Conn.get_req_header(conn, "authorization")})

    case Keyword.get(options, :response, :upgrade) do
      :upgrade ->
        Plug.Conn.upgrade_adapter(
          conn,
          :websocket,
          {Vxpipe.CallEngine.TestSpeechWireSession, owner, []}
        )

      :reject ->
        conn
        |> Plug.Conn.put_resp_header("x-provider-detail", "synthetic-rejected-secret")
        |> Plug.Conn.send_resp(401, "synthetic-rejected-secret")

      :stall ->
        send(owner, {:speech_wire_stalled, self()})

        receive do
          :release -> Plug.Conn.send_resp(conn, 408, "timeout")
        after
          5_000 -> Plug.Conn.send_resp(conn, 408, "timeout")
        end
    end
  end
end
