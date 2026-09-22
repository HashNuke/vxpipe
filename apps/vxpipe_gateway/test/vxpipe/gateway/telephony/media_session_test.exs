defmodule Vxpipe.Gateway.Telephony.MediaSessionTest do
  use ExUnit.Case, async: false

  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler
  }

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket, Submission}
  alias Vxpipe.Calls.{PreparedCall, TelephonyAdmissionClaim}
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.Media.{AudioOutput, OutputArbiter, RoomAudioEgress}

  alias Vxpipe.Gateway.Telephony.{
    IncomingLegActivationResult,
    MediaBinding,
    MediaSupervisor
  }

  @application_voip 2_048
  @automatic_bitrate -1_000
  @signal_voice 3_001

  test "attaches one supervised Telnyx media session and ends it with the exact socket" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assistant = Map.fetch!(plan.participants, plan.entry_receiver)
    assert {:ok, room} = CallEngine.start_call(plan)

    leg =
      start_supervised!(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: :telephony_media_test_leg
      )

    binding = binding(plan, room.incarnation_id, caller.participant_id, leg)
    socket = socket(self(), binding)
    claim = claim(plan, room.incarnation_id, caller.participant_id)
    root = start_supervised!({MediaSupervisor, name: nil})

    assert :ok =
             CallAdmission.handle_live_event(
               [telephony_media_supervisor: root],
               claim,
               activation(binding),
               socket,
               media_started_event(binding, "stream-1")
             )

    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    assert {:ok, snapshot} = MediaSupervisor.snapshot(binding.client_state_leg_id)
    connection = snapshot.connection
    assert is_pid(snapshot.audio_output)
    assert is_pid(snapshot.room_audio_ingress)
    assert is_pid(snapshot.room_audio_egress)
    assert {:ok, private_output, :ready} = OutputArbiter.readiness(snapshot.audio_output)
    assert private_output.scope == {:participant, caller.participant_id}
    assert {:ok, _room_output, :ready} = RoomAudioEgress.readiness(snapshot.room_audio_egress)

    assert {:ok, [media_connection, input, transport]} =
             Vxpipe.Gateway.Telephony.MediaSession.readiness_resources(
               binding.client_state_leg_id,
               input?: true
             )

    assert transport.instance == socket
    assert input.kind == :media_input

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: caller.participant_id,
      connection_id: binding.client_state_leg_id
    }

    policy =
      room.incarnation_id
      |> Vxpipe.CallEngine.MediaPolicy.Authority.whereis()
      |> Vxpipe.CallEngine.MediaPolicy.Authority.snapshot()

    assert {:ok, graph} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare(
               media_connection.instance,
               identity,
               policy,
               audio_input?: true,
               room_output?: true
             )

    assert MapSet.new(graph, & &1.kind) ==
             MapSet.new([
               :media_connection,
               :media_input,
               :phone_transport,
               :private_output,
               :audio_output,
               :room_audio_ingress,
               :audio_input,
               :room_audio_egress,
               :audio_subscription,
               :room_output_binding
             ])

    collector =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "phone-media",
         resources: graph,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000

    assert {:ok, media_track} =
             Vxpipe.Gateway.Telephony.MediaSession.input_track(binding.client_state_leg_id)

    assert media_track == %{track_id: "stream-1", codec: :opus, sample_rate: 16_000, channels: 1}

    assert {:ok, preparation} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare_graph(
               media_connection.instance,
               identity,
               policy,
               audio_input?: true,
               room_output?: true
             )

    assert preparation.resources == graph
    assert preparation.input_track == media_track
    assert preparation.identity == identity

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
               activation(binding),
               socket,
               media_event(binding, "stream-1")
             )

    assert {:error, :wrong_media_source} =
             CallAdmission.handle_live_event(
               [],
               claim,
               activation(binding),
               self(),
               media_event(binding, "stream-1")
             )

    assert {:ok, ^media_connection, :ready} =
             Vxpipe.Gateway.Telephony.MediaSession.readiness(binding.client_state_leg_id)

    assert {:ok, ^graph} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare(
               media_connection.instance,
               identity,
               policy,
               audio_input?: true,
               room_output?: true
             )

    send(socket, {:test_stream, "wrong-stream", self()})
    assert_receive :test_stream_changed

    assert {:ok, _resource, :failed} =
             Vxpipe.Gateway.Telephony.MediaSession.readiness(binding.client_state_leg_id)

    assert {:error, :unavailable} =
             Vxpipe.Gateway.Telephony.MediaSession.input_track(binding.client_state_leg_id)

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

    leg =
      start_supervised!(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: :telephony_room_end_test_leg
      )

    binding = binding(plan, room.incarnation_id, caller.participant_id, leg)
    socket = socket(self(), binding)
    claim = claim(plan, room.incarnation_id, caller.participant_id)
    root = start_supervised!({MediaSupervisor, name: nil})

    assert :ok =
             CallAdmission.handle_live_event(
               [telephony_media_supervisor: root],
               claim,
               activation(binding),
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

  test "prepares the exact native STS input and opens a room without human STT" do
    application = Vxpipe.CallEngine.Application
    original = Application.fetch_env!(:vxpipe_call_engine, application)

    Application.put_env(
      :vxpipe_call_engine,
      application,
      Keyword.put(
        original,
        :speech_to_speech,
        providers: %{Vxpipe.Providers.MorseCode.STSSession => [enabled: true]}
      )
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, application, original) end)

    plan = compile_plan(sts?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end}, id: :sts_leg)
    binding = binding(plan, room.incarnation_id, caller.participant_id, leg)
    socket = socket(self(), binding)
    claim = claim(plan, room.incarnation_id, caller.participant_id)
    root = start_supervised!({MediaSupervisor, name: nil})

    assert :ok =
             CallAdmission.handle_live_event(
               [telephony_media_supervisor: root],
               claim,
               activation(binding),
               socket,
               media_started_event(binding, "stream-1")
             )

    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    assert {:ok, snapshot} = MediaSupervisor.snapshot(binding.client_state_leg_id)
    assert snapshot.attachment.media_ingress == nil

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: caller.participant_id,
      connection_id: binding.client_state_leg_id
    }

    authority = Vxpipe.CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)
    policy = Vxpipe.CallEngine.MediaPolicy.Authority.snapshot(authority)

    assert {:ok, connection_resource, :ready} =
             Vxpipe.Gateway.Telephony.MediaSession.readiness(binding.client_state_leg_id)

    connection = connection_resource.instance
    # STS alone must demand an input track even without room input or human STT.
    assert {:ok, graph} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare_graph(
               connection,
               identity,
               policy,
               speech_to_speech?: true
             )

    assert graph.input_track == %{
             track_id: "stream-1",
             codec: :opus,
             sample_rate: 16_000,
             channels: 1
           }

    assert {:ok, %{ingress: ingress}} =
             CallEngine.speech_to_speech_input_configuration(snapshot.attachment)

    assert {:ok, resource, :ready} = Vxpipe.CallEngine.Media.STSIngress.readiness(ingress)
    assert resource in graph.resources
    assert resource.policy_interval == policy.revision
    Vxpipe.CallEngine.TestCallStartup.await_open(plan)

    assert {:ok, native_binding} = GenServer.call(connection, :vxpipe_connection_readiness)

    demand = %{
      audio_input?: false,
      room_output?: false,
      speech_to_text?: false,
      speech_to_speech?: true
    }

    assert {:error, :speech_to_speech_unavailable} =
             Vxpipe.Gateway.Media.ConnectionReadiness.prepare_binding(
               %{
                 native_binding
                 | attachment: %{native_binding.attachment | speech_to_speech_input: nil}
               },
               policy,
               demand
             )

    assert {:error, :policy_not_prepared} =
             Vxpipe.Gateway.Media.ConnectionReadiness.prepare_binding(
               native_binding,
               %{policy | revision: policy.revision + 1},
               demand
             )
  end

  defp compile_plan(options \\ []) do
    call_spec_input = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{
        capabilities: %{model_inference: %{provider: "fixture", model: "google:test-model"}}
      },
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

    call_spec_input =
      if Keyword.get(options, :sts?, false) do
        call_spec_input
        |> put_in([:defaults, :capabilities], %{})
        |> put_in(
          [:participants, "assistant", :capabilities],
          %{speech_to_speech: %{provider: "morse", model: "morse", options: %{}}}
        )
      else
        call_spec_input
      end

    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input,
               resource_id: unique_id("call-spec"),
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: call_spec.resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "telephony"}
               },
               tenant_id: unique_id("tenant"),
               actor_id: unique_id("actor"),
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      host_tools: %{}
    }

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries)
    plan
  end

  defp claim(plan, incarnation_id, participant_id) do
    %TelephonyAdmissionClaim{
      call: %PreparedCall{
        id: plan.call_id,
        tenant_key: plan.tenant_id,
        call_spec_id: plan.call_spec_id,
        call_spec_revision: plan.call_spec_revision,
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
      service_id: "10000000-0000-4000-8000-000000000001",
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

  defp activation(binding) do
    %IncomingLegActivationResult{
      binding: binding,
      media_url: "wss://voice.example.test/api/telephony/telnyx/media/test",
      submission: %Submission{
        status: :accepted,
        provider_call_control_id: binding.provider_call_control_id,
        provider_call_leg_id: binding.provider_call_leg_id,
        provider_call_session_id: binding.provider_call_session_id
      }
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

  defp socket(observer, binding) do
    start_supervised!(
      {Task,
       fn ->
         state = %{
           binding: binding,
           stream_id: "stream-1",
           readiness_resource: Vxpipe.Gateway.Telephony.SocketReadiness.new(binding)
         }

         socket_loop(observer, state)
       end}
    )
  end

  defp socket_loop(observer, state) do
    receive do
      {:vxpipe_playback_command, "stream-1", action, receiver, request} ->
        alias Vxpipe.Gateway.Telephony.PlaybackMarks

        {:ok, frames, marks} =
          PlaybackMarks.command(%PlaybackMarks{}, :telnyx, "stream-1", action, receiver, request)

        Enum.each(frames, fn {:text, message} ->
          case JSON.decode!(message) do
            %{"event" => "mark", "mark" => %{"name" => name}} ->
              PlaybackMarks.acknowledge(marks, name)

            %{"event" => "clear"} ->
              :ok
          end
        end)

        socket_loop(observer, state)

      {:vxpipe_telnyx_socket_send, message} ->
        send(observer, {:test_telnyx_socket_send, message})
        socket_loop(observer, state)

      {:vxpipe_phone_readiness, receiver, reference} ->
        Vxpipe.Gateway.Telephony.SocketReadiness.reply(state, receiver, reference)
        socket_loop(observer, state)

      {:test_stream, stream, sender} ->
        send(sender, :test_stream_changed)
        socket_loop(observer, %{state | stream_id: stream})

      :stop ->
        :ok
    end
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
