defmodule Vxpipe.Gateway.Telephony.MediaAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.{MediaAdmission, MediaBinding}

  setup do
    clock = :atomics.new(1, [])
    :atomics.put(clock, 1, 10_000)

    server =
      start_supervised!({MediaAdmission, name: nil, clock: fn -> :atomics.get(clock, 1) end})

    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    %{binding: media_binding(leg), clock: clock, leg: leg, server: server}
  end

  test "issues one opaque token and consumes it once for the exact ingress", context do
    assert {:ok, token} = MediaAdmission.issue(context.server, context.binding, 60_000)
    assert is_binary(token)
    assert byte_size(token) >= 32

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-other", token)

    assert {:ok, context.binding} ==
             MediaAdmission.consume(context.server, "ingress-primary", token)

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)
  end

  test "returns the same unconsumed token when command preparation repeats", context do
    assert {:ok, token} = MediaAdmission.issue(context.server, context.binding, 60_000)
    assert {:ok, ^token} = MediaAdmission.issue(context.server, context.binding, 60_000)
  end

  test "rejects expired tokens", context do
    assert {:ok, token} = MediaAdmission.issue(context.server, context.binding, 100)
    :atomics.put(context.clock, 1, 10_100)

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)
  end

  test "revokes the token when its exact leg terminates", context do
    assert {:ok, token} = MediaAdmission.issue(context.server, context.binding, 60_000)
    monitor = Process.monitor(context.leg)
    send(context.leg, :stop)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    _ = :sys.get_state(context.server)

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)
  end

  test "allows its owner to revoke an unconsumed leg admission", context do
    assert {:ok, token} = MediaAdmission.issue(context.server, context.binding, 60_000)
    assert :ok = MediaAdmission.revoke(context.server, context.leg)

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)
  end

  defp media_binding(leg) do
    %MediaBinding{
      provider: :telnyx,
      service_id: "primary-phone",
      ingress_key: "ingress-primary",
      tenant_id: "tenant-demo",
      call_id: "call-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-caller",
      provider_connection_id: "voice-app-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      client_state_leg_id: "leg-1",
      leg: leg
    }
  end
end
