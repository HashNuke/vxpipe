defmodule Vxpipe.Gateway.RTVI.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.RTVI.Codec

  test "answers a current RTVI 2.x client-ready message with bot-ready" do
    client_ready =
      JSON.encode!(%{
        "id" => "ready-1",
        "label" => "rtvi-ai",
        "type" => "client-ready",
        "data" => %{
          "version" => "2.1.0",
          "about" => %{"library" => "@pipecat-ai/client-js", "library_version" => "1.13.0"}
        }
      })

    assert {:reply, reply} = Codec.handle(client_ready)

    assert %{
             "id" => "ready-1",
             "label" => "rtvi-ai",
             "type" => "bot-ready",
             "data" => %{
               "version" => "2.1.0",
               "about" => %{"library" => "vxpipe", "library_version" => "0.1.0"}
             }
           } = JSON.decode!(reply)
  end

  test "rejects unsupported protocol majors without closing the transport" do
    client_ready =
      JSON.encode!(%{
        "id" => "ready-future",
        "label" => "rtvi-ai",
        "type" => "client-ready",
        "data" => %{
          "version" => "3.0.0",
          "about" => %{"library" => "future-client"}
        }
      })

    assert {:reply, reply} = Codec.handle(client_ready)

    assert %{
             "id" => "ready-future",
             "label" => "rtvi-ai",
             "type" => "error-response",
             "data" => %{"error" => error}
           } = JSON.decode!(reply)

    assert error =~ "not compatible"
  end

  test "rejects malformed semantic versions" do
    client_ready =
      JSON.encode!(%{
        "id" => "ready-malformed",
        "label" => "rtvi-ai",
        "type" => "client-ready",
        "data" => %{"version" => "2.-1.0"}
      })

    assert {:reply, reply} = Codec.handle(client_ready)

    assert %{
             "id" => "ready-malformed",
             "type" => "error-response"
           } = JSON.decode!(reply)
  end

  test "ignores Small WebRTC signalling and keepalive messages" do
    assert :ignore =
             Codec.handle(
               JSON.encode!(%{
                 "type" => "signalling",
                 "message" => %{"type" => "trackStatus", "receiver_index" => 0, "enabled" => true}
               })
             )

    assert :ignore = Codec.handle("ping: 1788470000000")
  end
end
