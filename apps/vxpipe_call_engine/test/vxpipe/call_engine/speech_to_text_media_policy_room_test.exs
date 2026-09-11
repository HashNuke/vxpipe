defmodule Vxpipe.CallEngine.SpeechToTextMediaPolicyRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestCallLifecycleTimer,
    TestSpeechToTextTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, JoinParticipant}
  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux

  test "planned room binds STT to its current media policy before accepting audio" do
    configure_speech_to_text()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    attachment = attach(plan, room, caller, "conn-stt-policy")

    assert_receive {:test_stt_transport_started, transport, _connection}
    assert_receive {:test_stt_transport_closed, ^transport}

    assert :ok =
             CallEngine.push_audio(
               attachment,
               audio_frame(plan, room, caller, "conn-stt-policy", 1)
             )

    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  test "keeps live-only STT running and stops it when no consumer remains" do
    configure_speech_to_text()

    plan =
      compile_plan(
        media_policy: %{
          transcript_routes: %{"caller" => ["receiver"]},
          save_transcripts: false
        },
        restrictor?: true
      )

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    restrictor = Map.fetch!(plan.participants, "restrictor")

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    caller_attachment = attach(plan, room, caller, "conn-live-caller")
    assert_receive {:test_stt_transport_started, transport, _connection}
    refute_receive {:test_stt_transport_closed, ^transport}

    _receiver_attachment = attach(plan, room, receiver, "conn-live-receiver")

    assert :ok =
             CallEngine.push_audio(
               caller_attachment,
               audio_frame(plan, room, caller, "conn-live-caller", 1)
             )

    assert_receive {:test_stt_audio, ^transport, <<1>>}

    TestSpeechToTextTransport.deliver(
      transport,
      turn_message("StartOfTurn", 1, "live only")
    )

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: caller_participant_id,
                      text: "live only",
                      final: false
                    }}

    assert caller_participant_id == caller.participant_id

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _participant} = CallEngine.join_participant(join)
    assert_receive {:test_stt_transport_closed, ^transport}

    assert :ok =
             CallEngine.push_audio(
               caller_attachment,
               audio_frame(plan, room, caller, "conn-live-caller", 2)
             )

    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  defp compile_plan(options \\ []) do
    media_policy =
      Keyword.get(options, :media_policy, %{transcript_routes: %{}, save_transcripts: false})

    participants = %{
      "caller" => human_participant(%{speech_to_text: "plan-stt"}),
      "receiver" => human_participant(%{})
    }

    participants =
      if Keyword.get(options, :restrictor?, false) do
        Map.put(
          participants,
          "restrictor",
          Map.put(human_participant(%{}), :while_present, %{
            transcript_routes: %{},
            save_transcripts: false
          })
        )
      else
        participants
      end

    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      media_policy: media_policy,
      call_variables: %{sections: %{}},
      participants: participants,
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "stt-policy-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "stt-policy-room", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-stt-policy",
               actor_id: "actor-stt-policy",
               call_id: unique_id("call-stt-policy"),
               room_id: unique_id("room-stt-policy")
             )

    registries = %{
      capability_profiles: %{
        "plan-stt" => %{
          kind: :speech_to_text,
          provider: Flux,
          options: %{model: "flux-general-multi", encoding: :opus, sample_rate: 48_000}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp human_participant(capabilities) do
    %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: capabilities
    }
  end

  defp attach(plan, room, participant, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} = CallEngine.attach_connection(command)
    attachment
  end

  defp audio_frame(plan, room, participant, connection_id, sequence_number) do
    %AudioFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: connection_id,
      track_id: "track-stt-policy",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: sequence_number,
      timestamp: sequence_number * 960,
      payload: <<1>>,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp turn_message(event, sequence, transcript) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "request-live-only",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    })
  end

  defp configure_speech_to_text do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [api_key: "runtime-secret"],
      transport: {TestSpeechToTextTransport, [observer: self()]},
      media_ingress: [
        maximum_frames: 8,
        maximum_bytes: 1024,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 2
      ]
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_text, speech_to_text)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
