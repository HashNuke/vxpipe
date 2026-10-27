defmodule Vxpipe.Providers.ElevenLabs.RealtimeAPITest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeAPI}

  test "mints only a model-scoped ephemeral credential, never an agent" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/convai/realtime/client_secrets"
      assert Plug.Conn.get_req_header(conn, "xi-api-key") == ["synthetic-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      assert request["session"]["model"] == "eleven_realtime_v1_mini"
      assert request["session"]["audio"]["input"]["turn_detection"]["type"] == "semantic_vad"

      Req.Test.json(conn, %{
        "value" => "synthetic-ephemeral",
        "expires_at" => System.os_time(:second) + 60
      })
    end)

    {:ok, config} = Realtime.new(api_key: "synthetic-key")
    assert {:ok, connection} = RealtimeAPI.connect(config, plug: {Req.Test, __MODULE__})
    assert connection.url == "wss://api.elevenlabs.io/v1/convai/realtime"
    refute inspect(connection) =~ "synthetic-ephemeral"
    refute inspect(connection) =~ "synthetic-key"
  end

  test "HTTP failures are bounded and never expose provider bodies" do
    Req.Test.expect(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 403, "synthetic-private-provider-detail")
    end)

    {:ok, config} = Realtime.new(api_key: "synthetic-key")

    assert {:error, {:provider_rejected, 403}} =
             RealtimeAPI.connect(config, plug: {Req.Test, __MODULE__})
  end
end
