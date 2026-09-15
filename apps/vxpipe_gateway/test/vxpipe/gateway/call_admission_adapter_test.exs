defmodule Vxpipe.Gateway.CallAdmissionAdapterTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.CallDefinition.{ConnectionIntent, VariablePermissions}
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    CallVariables,
    Capabilities,
    Participant,
    ToolVisibility
  }

  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall}
  alias Vxpipe.Gateway.CallAdmission

  alias Vxpipe.Gateway.Telephony.{
    IncomingLegActivationResult,
    MediaAdmission,
    ServiceRegistry
  }

  alias Vxpipe.Gateway.TestTelephonyCallBackend

  test "joins the claimed pinned participant beneath an existing call incarnation" do
    tenant_id = unique_id("tenant")
    room_id = unique_id("room")
    participant_id = unique_id("support")
    plan = resolved_plan(tenant_id, room_id, participant_id)

    assert {:ok, create_room} =
             CreateRoom.new(
               tenant_id: tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(create_room)
    started_at = DateTime.add(DateTime.utc_now(), -1, :second)

    claim = %AdmissionClaim{
      call: prepared_call(plan, room.incarnation_id, started_at),
      token_id: unique_id("token"),
      participant_key: unique_id("route"),
      participant_ref: "support",
      participant_id: participant_id,
      accepted_at: DateTime.utc_now()
    }

    assert {:joined, participant} = CallAdmission.start_call([], claim)
    assert participant.tenant_id == tenant_id
    assert participant.room_id == room_id
    assert participant.incarnation_id == room.incarnation_id
    assert participant.participant_id == participant_id
    assert participant.role == :human
  end

  test "leaves a transfer-only human pending until its WebRTC connection attaches" do
    tenant_id = unique_id("tenant")
    room_id = unique_id("room")
    participant_id = unique_id("support")
    plan = resolved_plan(tenant_id, room_id, participant_id, :transfer)

    assert {:ok, create_room} =
             CreateRoom.new(
               tenant_id: tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(create_room)
    started_at = DateTime.add(DateTime.utc_now(), -1, :second)

    claim = %AdmissionClaim{
      call: prepared_call(plan, room.incarnation_id, started_at),
      token_id: unique_id("token"),
      participant_key: unique_id("route"),
      participant_ref: "support",
      participant_id: participant_id,
      accepted_at: DateTime.utc_now()
    }

    assert {:transfer_pending, pending} = CallAdmission.start_call([], claim)
    assert pending.participant_id == participant_id
    assert pending.kind == :human

    assert {:error, %{code: :participant_not_found}} =
             CallEngine.participant_snapshot(tenant_id, room_id, participant_id)
  end

  test "does not let a transfer-only destination start a prepared call" do
    tenant_id = unique_id("tenant")
    room_id = unique_id("room")
    participant_id = unique_id("support")
    plan = resolved_plan(tenant_id, room_id, participant_id, :transfer)

    claim = %AdmissionClaim{
      call: prepared_call(plan, nil, nil, :prepared),
      token_id: unique_id("token"),
      participant_key: unique_id("route"),
      participant_ref: "support",
      participant_id: participant_id,
      accepted_at: DateTime.utc_now()
    }

    assert {:join_error, :participant_start_failed} = CallAdmission.start_call([], claim)
    assert Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}) == []
  end

  test "rejects an unbound hosted incoming plan before starting its room" do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})
    claim = TestTelephonyCallBackend.claim(backend)

    options = [
      id: claim.service,
      ingress_key: "incoming-pin-test",
      provider: :telnyx,
      scope: {:tenant, claim.call.tenant_key},
      provider_connection_id: claim.provider_connection_id,
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "test-key"
    ]

    snapshot = Vxpipe.Gateway.TestTelephonyServiceRepository.snapshot(options)

    {:ok, service} =
      Vxpipe.Gateway.Telephony.ConfiguredService.from_snapshot(
        snapshot,
        "https://voice.example.test"
      )

    assert {:error, :telephony_service_mismatch} =
             CallAdmission.start_incoming([], claim, service)

    assert Registry.lookup(CallEngine.RoomRegistry, {claim.call.tenant_key, claim.call.room_id}) ==
             []
  end

  test "web startup rejects unbound or stale later phone destinations before creating a room" do
    for failure <- [:unbound, :stale] do
      plan = Vxpipe.Gateway.PhoneTransferScenario.compile_plan()
      phone = Map.fetch!(plan.participants, "human-support")
      caller = Map.fetch!(plan.participants, "caller")
      phone = if failure == :unbound, do: %{phone | telephony_service: nil}, else: phone
      plan = %{plan | participants: Map.put(plan.participants, "human-support", phone)}
      observer = self()

      registry =
        ServiceRegistry.init!(
          enabled: true,
          telephony_service_repository:
            {Vxpipe.Gateway.TestTelephonyServiceRepository,
             fn :resolve, _arguments ->
               send(observer, :fresh_phone_lookup)
               {:error, :provider_credential_unavailable}
             end}
        )

      claim = %AdmissionClaim{
        call: prepared_call(plan, nil, nil, :prepared),
        token_id: unique_id("token"),
        participant_key: unique_id("route"),
        participant_ref: "caller",
        participant_id: caller.participant_id,
        accepted_at: DateTime.utc_now()
      }

      assert {:error, :room_start_failed} =
               CallAdmission.start_call([service_registry: registry], claim)

      assert Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) == []

      if failure == :stale,
        do: assert_receive(:fresh_phone_lookup),
        else: refute_receive(:fresh_phone_lookup)
    end
  end

  test "activates an incoming leg through its configured service" do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})
    admission = start_supervised!({MediaAdmission, name: nil})
    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [
          [
            id: "primary-phone",
            ingress_key: "ingress_telnyx_primary",
            scope: {:tenant, "AAAAAAAAAAAAAAAA"},
            provider: :telnyx,
            provider_connection_id: "voice-application-1",
            public_key: Base.encode64(:binary.copy(<<1>>, 32)),
            api_key: "accept",
            public_base_url: "https://voice.example.test",
            adapter: Vxpipe.Gateway.TestTelephonyAdapter
          ]
        ]
      )

    {:ok, service} = ServiceRegistry.fetch(registry, "ingress_telnyx_primary")
    reference = service.identity.service_reference
    original = TestTelephonyCallBackend.claim(backend)
    participant = %{participant_id: original.participant_id, telephony_service: reference}
    plan = %{original.call.plan | participants: %{"caller" => participant}}
    claim = %{original | call: %{original.call | plan: plan}, service_id: reference.service_id}

    room = %RoomSnapshot{
      tenant_id: "AAAAAAAAAAAAAAAA",
      room_id: "60000000-0000-4000-8000-000000000006",
      incarnation_id: "rinc_phone-1",
      lifecycle: :open,
      created_by_actor_id: "actor_phone",
      created_by_command_id: "cmd_phone-start"
    }

    assert {:ok,
            %IncomingLegActivationResult{
              binding: binding,
              submission: submission
            }} =
             CallAdmission.activate_incoming(
               [
                 service_registry: registry,
                 media_admission: admission,
                 telephony_leg_id: fn -> "tleg-incoming-default" end
               ],
               service,
               claim,
               room,
               leg
             )

    assert binding.incarnation_id == room.incarnation_id
    assert binding.leg == leg
    assert submission.status == :accepted
    assert_receive {:test_telephony_answer, _request}
  end

  defp prepared_call(plan, incarnation_id, started_at, state \\ :running) do
    %PreparedCall{
      id: plan.call_id,
      tenant_key: plan.tenant_id,
      definition_id: plan.definition_id,
      definition_revision: plan.definition_revision,
      schema_version: plan.schema_version,
      participant_routes: %{},
      entry_caller: plan.entry_caller,
      entry_receiver: plan.entry_receiver,
      initial_variables: %{},
      plan: plan,
      plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
      state: state,
      room_id: plan.room_id,
      created_at: started_at || DateTime.utc_now(),
      started_at: started_at,
      ended_at: nil,
      incarnation_id: incarnation_id,
      terminal_reason: nil
    }
  end

  defp resolved_plan(tenant_id, room_id, participant_id, admission \\ :start_call) do
    participant = %Participant{
      definition_key: "support",
      participant_id: participant_id,
      activation_id: nil,
      kind: :human,
      description: nil,
      connection: %ConnectionIntent{service: :web, mode: :receive, admission: admission},
      transfer_notice: nil,
      prompt: nil,
      first_message: nil,
      first_message_text: nil,
      capabilities: %Capabilities{},
      while_present: Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy.inherit(),
      tools: %{},
      transfers: [],
      transfer_history: nil,
      variable_permissions: %VariablePermissions{}
    }

    %ResolvedCallPlan{
      definition_id: unique_id("definition"),
      definition_revision: 1,
      schema_version: "20260913.01",
      tenant_id: tenant_id,
      actor_id: unique_id("actor"),
      call_id: unique_id("call"),
      room_id: room_id,
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy.inherit(),
      participants: %{"support" => participant},
      transfer_policy: %Vxpipe.CallEngine.CallDefinition.TransferPolicy{
        attempt_timeout_ms: 30_000
      },
      call_variables: %CallVariables{},
      tool_visibility: ToolVisibility.hidden(),
      max_duration_ms: 60_000
    }
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
