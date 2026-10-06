defmodule Vxpipe.Console.LiveTelephonyPeerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.Test.{ConfiguredTelephonyFixture, LiveTelephonyPeer}
  alias Vxpipe.Gateway.Telephony.MediaBinding

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  test "press-1 and hangup address only the correlated Telnyx peer without retry" do
    {fixture, call, binding} = context()
    assert {:ok, peer} = LiveTelephonyPeer.new(fixture, call, binding)

    for {operation, action} <- [{:press_one, "send_dtmf"}, {:hangup, "hangup"}] do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.host == "api.telnyx.com"
        assert conn.request_path == "/v2/calls/opaque%2Fcontrol/actions/#{action}"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer synthetic-peer-key"]
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = JSON.decode!(body)
        assert is_binary(payload["command_id"])

        if operation == :press_one do
          assert payload["digits"] == "1"
          assert payload["duration_millis"] == 250
        else
          refute Map.has_key?(payload, "digits")
        end

        Req.Test.json(conn, %{data: %{result: "ok"}})
      end)

      assert :ok = apply(LiveTelephonyPeer, operation, [peer, [plug: {Req.Test, __MODULE__}]])
    end
  end

  test "an ambiguous carrier response remains an error without another command" do
    {fixture, call, binding} = context()
    assert {:ok, peer} = LiveTelephonyPeer.new(fixture, call, binding)

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{error: "private upstream body"})
    end)

    assert {:error, {:peer_command_rejected, 503}} =
             LiveTelephonyPeer.press_one(peer, plug: {Req.Test, __MODULE__})
  end

  test "foreign tenant, room, call, incarnation, participant and service cannot become a peer" do
    {fixture, call, binding} = context()

    for field <- [
          :tenant_id,
          :room_id,
          :call_id,
          :incarnation_id,
          :participant_id,
          :service_id,
          :provider_connection_id
        ] do
      assert {:error, :unbound_peer} =
               LiveTelephonyPeer.new(fixture, call, Map.replace!(binding, field, "foreign"))
    end

    assert {:error, :unbound_peer} =
             LiveTelephonyPeer.new(fixture, call, %{binding | provider: :twilio})

    assert {:error, :unbound_peer} =
             LiveTelephonyPeer.new(fixture, call, %{binding | provider_call_control_id: ""})
  end

  test "the media binding uses the pinned service name rather than its persistence ID" do
    {fixture, call, binding} = context()

    call =
      put_in(call, [:plan, :participants, "human", :telephony_service, :service_id], "record-id")

    assert {:ok, _peer} = LiveTelephonyPeer.new(fixture, call, binding)

    assert {:error, :unbound_peer} =
             LiveTelephonyPeer.new(fixture, call, %{binding | service_id: "record-id"})
  end

  test "peer inspection does not expose the API key or call control token" do
    {fixture, call, binding} = context()
    assert {:ok, peer} = LiveTelephonyPeer.new(fixture, call, binding)
    rendered = inspect(peer)
    refute rendered =~ "synthetic-peer-key"
    refute rendered =~ "opaque/control"
  end

  defp context do
    fixture = %ConfiguredTelephonyFixture{
      tenant: %{key: "tenant"},
      settings: %{telnyx_key: "synthetic-peer-key", application_id: "application"}
    }

    human = %{
      participant_id: "human-id",
      telephony_service: %{
        service_id: "service",
        name: "service",
        provider: "telnyx",
        provider_connection_id: "application"
      }
    }

    call = %{
      id: "call",
      room_id: "room",
      incarnation_id: "incarnation",
      plan: %{entry_caller: "human", participants: %{"human" => human}}
    }

    binding = %MediaBinding{
      provider: :telnyx,
      service_id: "service",
      ingress_key: "ingress",
      tenant_id: "tenant",
      call_id: "call",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human-id",
      provider_connection_id: "application",
      provider_call_control_id: "opaque/control",
      provider_call_leg_id: "provider-leg",
      provider_call_session_id: "session",
      client_state_leg_id: "leg",
      leg: self()
    }

    {fixture, call, binding}
  end
end
