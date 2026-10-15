defmodule Vxpipe.Gateway.MCPSlowBodyTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls.Principal
  alias Vxpipe.Gateway.MCP.{Admission, Endpoint}

  @moduletag :integration
  @moduletag capture_log: true

  test "a stalled authenticated body times out and releases the real listener's request lease" do
    admission = start_supervised!({Admission, name: nil, max_concurrency: 1})

    listener =
      start_supervised!(
        {Bandit,
         plug:
           {Endpoint,
            enabled: true,
            allowed_hosts: ["127.0.0.1"],
            allow_loopback_http: true,
            admission: admission,
            authentication: {__MODULE__, self()},
            read_timeout: 100},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
    on_exit(fn -> :gen_tcp.close(socket) end)

    :ok =
      :gen_tcp.send(socket, [
        "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:",
        Integer.to_string(port),
        "\r\nAuthorization: Bearer slow-key\r\nContent-Type: application/json",
        "\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n{"
      ])

    # Authentication is a project-owned barrier after admission acquisition.
    assert_receive {:authenticated, request}, 1_000
    monitor = Process.monitor(request)
    assert probe(port).status == 503
    send(request, :read_body)

    {:ok, response} = :gen_tcp.recv(socket, 0, 2_000)
    assert response =~ "HTTP/1.1 408"
    assert_receive {:DOWN, ^monitor, :process, ^request, _reason}, 1_000
    _ = :sys.get_state(admission)
    assert probe(port).status == 405
  end

  def authenticate(observer, "slow-key") do
    send(observer, {:authenticated, self()})

    receive do
      :read_body -> authenticate(observer, "synthetic-key")
    after
      2_000 -> {:error, :authentication_unavailable}
    end
  end

  def authenticate(_observer, "synthetic-key"),
    do:
      {:ok,
       %Principal{
         tenant_key: "AAAAAAAAAAAAAAAA",
         api_key_id: "synthetic-key-id",
         scopes: MapSet.new([:calls])
       }}

  defp probe(port),
    do:
      Req.get!("http://127.0.0.1:#{port}/mcp",
        headers: [{"authorization", "Bearer synthetic-key"}],
        retry: false,
        receive_timeout: 1_000
      )
end
