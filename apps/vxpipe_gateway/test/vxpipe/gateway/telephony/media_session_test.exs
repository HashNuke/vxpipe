defmodule Vxpipe.Gateway.Telephony.MediaSessionTest do
  use ExUnit.Case, async: false

  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler
  }

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket}
  alias Vxpipe.Calls.{PreparedCall, TelephonyAdmissionClaim}
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.Media.AudioOutput
  alias Vxpipe.Gateway.Telephony.{MediaBinding, MediaSupervisor}

  @application_voip 2_048
  @automatic_bitrate -1_000
  @signal_voice 3_001

  test "attaches one supervised Telnyx media session and ends it with the exact socket" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assistant = Map.fetch!(plan.participants, plan.entry_receiver)
    assert {:ok, room} = CallEngine.start_call(plan)

    socket = socket(self())

    leg =
      start_supervised!(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: :telephony_media_test_leg
      )

    binding = binding(plan, room.incarnation_id, caller.participant_id, leg)
    claim = claim(plan, room.incarnation_id, caller.participant_id)
    root = start_supervised!({MediaSupervisor, name: nil})

    assert :ok =
             CallAdmission.handle_live_event(
               [telephony_media_supervisor: root],
               claim,
               {binding, :accepted_submission},
               socket,
               media_started_event(binding, "stream-1")
             )

    assert {:ok, snapshot} = MediaSupervisor.snapshot(binding.client_state_leg_id)
    connection = snapshot.connection
    assert is_pid(snapshot.audio_output)
    assert is_pid(snapshot.room_audio_ingress)
    assert is_pid(snapshot.room_audio_egress)

    assert :ok =
             AudioOutput.push(
               snapshot.audio_output,
               output_frame(binding, assistant.participant_id, self())
             )

    assert :ok = AudioOutput.finish(snapshot.audio_output, "turn-phone", self())
    assert_receive {:test_telnyx_socket_send, message}, 2_000
    assert %{"event" => "media"} = JSON.decode!(message)
    assert_receive {:vxpipe_audio_playback, _output, "turn-phone", :started}, 2_000
    assert_receive {:vxpipe_audio_playback, _output, "turn-phone", {:completed, 20}}, 2_000

    assert :ok =
             CallAdmission.handle_live_event(
               [],
               claim,
               {binding, :accepted_submission},
               socket,
               media_event(binding, "stream-1")
             )

    assert {:error, :wrong_media_source} =
             CallAdmission.handle_live_event(
               [],
               claim,
               {binding, :accepted_submission},
               self(),
               media_event(binding, "stream-1")
             )

    monitor = Process.monitor(connection)
    send(socket, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :shutdown}, 2_000

    assert {:error, :media_session_not_found} =
             MediaSupervisor.snapshot(binding.client_state_leg_id)
  end

  test "ends the supervised media session when its room ends" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, room} = CallEngine.start_call(plan)

    socket = socket(self())

    leg =
      start_supervised!(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: :telephony_room_end_test_leg
      )

    binding = binding(plan, room.incarnation_id, caller.participant_id, leg)
    claim = claim(plan, room.incarnation_id, caller.participant_id)
    root = start_supervised!({MediaSupervisor, name: nil})

    assert :ok =
             CallAdmission.handle_live_event(
               [telephony_media_supervisor: root],
               claim,
               {binding, :accepted_submission},
               socket,
               media_started_event(binding, "stream-1")
             )

    assert {:ok, %{connection: connection}} =
             MediaSupervisor.snapshot(binding.client_state_leg_id)

    [{room_authority, _value}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    monitor = Process.monitor(connection)
    GenServer.stop(room_authority, :shutdown)

    assert_receive {:DOWN, ^monitor, :process, ^connection, :shutdown}, 2_000

    assert {:error, :media_session_not_found} =
             MediaSupervisor.snapshot(binding.client_state_leg_id)
  end

  defp compile_plan do
    definition_input = %{
      schema_version: "20260911.03",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "primary-phone",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(definition_input,
               resource_id: unique_id("definition"),
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: definition.resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "telephony"}
               },
               tenant_id: unique_id("tenant"),
               actor_id: unique_id("actor"),
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "google:test-model"}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp claim(plan, incarnation_id, participant_id) do
    %TelephonyAdmissionClaim{
      call: %PreparedCall{
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
        state: :running,
        room_id: plan.room_id,
        created_at: DateTime.utc_now(),
        started_at: DateTime.utc_now(),
        ended_at: nil,
        incarnation_id: incarnation_id,
        terminal_reason: nil
      },
      participant_ref: plan.entry_caller,
      participant_id: participant_id,
      provider: :telnyx,
      service: "primary-phone",
      provider_event_id: "event-incoming-1",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      accepted_at: DateTime.utc_now()
    }
  end

  defp binding(plan, incarnation_id, participant_id, leg) do
    %MediaBinding{
      provider: :telnyx,
      service_id: "primary-phone",
      ingress_key: "ingress-primary",
      tenant_id: plan.tenant_id,
      call_id: plan.call_id,
      room_id: plan.room_id,
      incarnation_id: incarnation_id,
      participant_id: participant_id,
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      client_state_leg_id: unique_id("connection"),
      leg: leg
    }
  end

  defp output_frame(binding, speaking_participant_id, reply_to) do
    %AudioOutputFrame{
      tenant_id: binding.tenant_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: speaking_participant_id,
      connection_id: binding.client_state_leg_id,
      command_id: "command-phone",
      correlation_id: "turn-phone",
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      payload: :binary.copy(<<1_000::little-signed-16>>, 960),
      reply_to: reply_to
    }
  end

  defp media_event(binding, stream_id) do
    packet = encode(:binary.copy(<<1_000::little-signed-16>>, 320))

    %Event{
      kind: :media,
      provider: :telnyx,
      provider_event_id: "#{stream_id}:2",
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: binding.provider_call_session_id,
      stream_id: stream_id,
      sequence_number: 1,
      media: %MediaPacket{
        codec: :opus,
        sample_rate: 16_000,
        channels: 1,
        sequence_number: 1,
        timestamp: 0,
        payload: packet
      }
    }
  end

  defp media_started_event(binding, stream_id) do
    %Event{
      kind: :media_started,
      provider: :telnyx,
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: binding.provider_call_session_id,
      stream_id: stream_id
    }
  end

  defp encode(pcm) do
    encoder = Native.create(16_000, 1, @application_voip, @automatic_bitrate, @signal_voice)
    assert {:ok, packet} = Native.encode_packet(encoder, pcm, 320)
    packet
  end

  defp socket(observer) do
    start_supervised!(
      {Task,
       fn ->
         socket_loop(observer)
       end}
    )
  end

  defp socket_loop(observer) do
    receive do
      {:vxpipe_telnyx_socket_send, message} ->
        send(observer, {:test_telnyx_socket_send, message})
        socket_loop(observer)

      :stop ->
        :ok
    end
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
