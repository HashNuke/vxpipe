defmodule Vxpipe.AgentRuntime.DialogueWireServer do
  @moduledoc false
  @behaviour Plug

  def start(owner, response) do
    server =
      ExUnit.Callbacks.start_supervised!(
        {Bandit,
         plug: {__MODULE__, {owner, response}}, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
        id: make_ref()
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end

  @impl true
  def init(options), do: options

  @impl true
  def call(connection, {owner, response}) do
    {:ok, raw_body, connection} = Plug.Conn.read_body(connection)
    body = JSON.decode!(raw_body)
    send(owner, {:encoded_request, body})
    {type, encoded} = response.(body)

    connection
    |> Plug.Conn.put_resp_content_type(type)
    |> Plug.Conn.send_resp(200, encoded)
  end
end
