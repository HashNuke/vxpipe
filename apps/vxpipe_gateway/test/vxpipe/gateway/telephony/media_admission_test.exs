defmodule Vxpipe.Gateway.Telephony.MediaAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.{ConfiguredService, MediaAdmission, MediaBinding}

  setup do
    clock = :atomics.new(1, [])
    :atomics.put(clock, 1, 10_000)

    server =
      start_supervised!({MediaAdmission, name: nil, clock: fn -> :atomics.get(clock, 1) end})

    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    task_supervisor = start_supervised!({Task.Supervisor, name: nil})

    %{
      binding: media_binding(leg),
      clock: clock,
      leg: leg,
      server: server,
      task_supervisor: task_supervisor
    }
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

  test "reserves an outbound token before exact provider identifiers are known", context do
    assert {:ok, token} =
             MediaAdmission.reserve(context.server, "ingress-primary", context.leg, 60_000)

    consumer =
      Task.Supervisor.async_nolink(context.task_supervisor, fn ->
        MediaAdmission.consume(context.server, "ingress-primary", token)
      end)

    assert Task.yield(consumer, 50) == nil
    assert :ok = MediaAdmission.bind(context.server, context.binding)
    assert {:ok, {:ok, context.binding}} == Task.yield(consumer, 1_000)

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)
  end

  test "keeps a reserved token pending after a mismatched bind", context do
    assert {:ok, token} =
             MediaAdmission.reserve(context.server, "ingress-primary", context.leg, 60_000)

    mismatched = %{context.binding | ingress_key: "ingress-other"}
    assert {:error, :media_binding_mismatch} = MediaAdmission.bind(context.server, mismatched)

    consumer =
      Task.Supervisor.async_nolink(context.task_supervisor, fn ->
        MediaAdmission.consume(context.server, "ingress-primary", token)
      end)

    assert Task.yield(consumer, 50) == nil
    assert :ok = MediaAdmission.bind(context.server, context.binding)
    assert {:ok, {:ok, context.binding}} == Task.yield(consumer, 1_000)
  end

  test "revocation releases an upgrade waiting on a reserved token", context do
    assert {:ok, token} =
             MediaAdmission.reserve(context.server, "ingress-primary", context.leg, 60_000)

    consumer =
      Task.Supervisor.async_nolink(context.task_supervisor, fn ->
        MediaAdmission.consume(context.server, "ingress-primary", token)
      end)

    assert Task.yield(consumer, 50) == nil
    assert :ok = MediaAdmission.revoke(context.server, context.leg)

    assert {:ok, {:error, :invalid_media_token}} == Task.yield(consumer, 1_000)
  end

  test "an expired reservation cannot be bound and releases its waiting upgrade", context do
    assert {:ok, token} =
             MediaAdmission.reserve(context.server, "ingress-primary", context.leg, 100)

    consumer =
      Task.Supervisor.async_nolink(context.task_supervisor, fn ->
        MediaAdmission.consume(context.server, "ingress-primary", token)
      end)

    assert Task.yield(consumer, 50) == nil
    :atomics.put(context.clock, 1, 10_100)

    assert {:error, :media_admission_not_found} =
             MediaAdmission.bind(context.server, context.binding)

    assert {:ok, {:error, :invalid_media_token}} == Task.yield(consumer, 1_000)
  end

  test "looks up pending private auth without consuming, waiting or extending expiry", context do
    service = twilio_service()

    assert {:ok, token} =
             MediaAdmission.reserve(
               context.server,
               "ingress-primary",
               context.leg,
               10_000,
               service
             )

    assert {:ok, ^token} =
             MediaAdmission.reserve(
               context.server,
               "ingress-primary",
               context.leg,
               10_000,
               service
             )

    assert {:error, :leg_already_bound} =
             MediaAdmission.reserve(
               context.server,
               "ingress-primary",
               context.leg,
               10_000,
               twilio_service(auth_token: "changed-private-auth")
             )

    original = :sys.get_state(context.server)

    assert {:ok, ^service} =
             MediaAdmission.lookup_service(context.server, "ingress-primary", token)

    assert {:error, :invalid_media_token} =
             MediaAdmission.lookup_service(context.server, "wrong-ingress", token)

    assert :sys.get_state(context.server) == original
    refute inspect(original) =~ "retained-private-auth"

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(
               context.server,
               "ingress-primary",
               token,
               twilio_service(auth_token: "wrong-private-auth")
             )

    assert :sys.get_state(context.server) == original

    consumer =
      Task.Supervisor.async_nolink(context.task_supervisor, fn ->
        MediaAdmission.consume(context.server, "ingress-primary", token, service)
      end)

    assert Task.yield(consumer, 50) == nil
    binding = twilio_binding(context)

    assert {:error, :media_binding_mismatch} =
             MediaAdmission.bind(context.server, %{binding | tenant_id: "another-tenant"})

    assert :ok = MediaAdmission.bind(context.server, binding)
    assert {:ok, {:ok, ^binding}} = Task.yield(consumer, 1_000)

    assert {:error, :invalid_media_token} =
             MediaAdmission.lookup_service(context.server, "ingress-primary", token)
  end

  test "protects bound Twilio tokens and rejects incompatible configuration", context do
    service = twilio_service()
    invalid_scope = %{service | identity: %{service.identity | scope: :application}}
    binding = twilio_binding(context)

    assert {:error, :invalid_media_binding} =
             MediaAdmission.issue(context.server, binding, 60_000)

    assert {:error, :invalid_media_binding} =
             MediaAdmission.issue(
               context.server,
               binding,
               60_000,
               invalid_scope
             )

    assert {:error, :invalid_media_reservation} =
             MediaAdmission.reserve(
               context.server,
               "ingress-primary",
               context.leg,
               60_000,
               invalid_scope
             )

    assert {:error, :invalid_media_binding} =
             MediaAdmission.issue(
               context.server,
               %{binding | tenant_id: "another-tenant"},
               60_000,
               service
             )

    assert {:ok, token} = MediaAdmission.issue(context.server, binding, 60_000, service)
    assert {:ok, ^token} = MediaAdmission.issue(context.server, binding, 60_000, service)

    assert {:error, :leg_already_bound} =
             MediaAdmission.issue(
               context.server,
               binding,
               60_000,
               twilio_service(auth_token: "changed-private-auth")
             )

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", token)

    assert {:ok, ^binding} =
             MediaAdmission.consume(context.server, "ingress-primary", token, service)
  end

  test "an unsigned pending consumer cannot be given a Twilio binding", context do
    assert {:ok, token} =
             MediaAdmission.reserve(context.server, "ingress-primary", context.leg, 60_000)

    assert {:error, :invalid_media_token} =
             MediaAdmission.lookup_service(context.server, "ingress-primary", token)

    consumer =
      Task.Supervisor.async_nolink(context.task_supervisor, fn ->
        MediaAdmission.consume(context.server, "ingress-primary", token)
      end)

    assert Task.yield(consumer, 50) == nil

    assert {:error, :media_binding_mismatch} =
             MediaAdmission.bind(context.server, twilio_binding(context))

    assert :ok = MediaAdmission.bind(context.server, context.binding)
    assert {:ok, {:ok, context.binding}} == Task.yield(consumer, 1_000)
  end

  test "private lookup honors expiry and revocation without adopting a replacement token",
       context do
    service = twilio_service()
    binding = twilio_binding(context)
    assert {:ok, expired} = MediaAdmission.issue(context.server, binding, 10_000, service)
    :atomics.put(context.clock, 1, 20_000)

    assert {:error, :invalid_media_token} =
             MediaAdmission.lookup_service(context.server, "ingress-primary", expired)

    assert {:ok, replaced} = MediaAdmission.issue(context.server, binding, 10_000, service)
    refute replaced == expired

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.server, "ingress-primary", expired, service)

    assert {:ok, ^service} =
             MediaAdmission.lookup_service(context.server, "ingress-primary", replaced)

    assert :ok = MediaAdmission.revoke(context.server, context.leg)

    assert {:error, :invalid_media_token} =
             MediaAdmission.lookup_service(context.server, "ingress-primary", replaced)
  end

  defp twilio_binding(context) do
    %{
      context.binding
      | provider: :twilio,
        provider_connection_id: "AC00000000000000000000000000000000",
        provider_call_session_id: nil
    }
  end

  defp twilio_service(overrides \\ []) do
    {:ok, service} =
      ConfiguredService.new(
        Keyword.merge(
          [
            id: "primary-phone",
            ingress_key: "ingress-primary",
            scope: {:tenant, "tenant-demo"},
            provider: :twilio,
            account_sid: "AC00000000000000000000000000000000",
            auth_token: "retained-private-auth",
            public_base_url: "https://voice.example.test/voice"
          ],
          overrides
        )
      )

    service
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
