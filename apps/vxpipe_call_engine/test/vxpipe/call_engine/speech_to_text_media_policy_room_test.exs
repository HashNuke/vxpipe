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

  alias Vxpipe.CallEngine.Command.AttachConnection
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

    attachment = attach(plan, room, caller)

    assert_receive {:test_stt_transport_started, transport, _connection}
    assert_receive {:test_stt_transport_closed, ^transport}

    assert :ok = CallEngine.push_audio(attachment, audio_frame(plan, room, caller))
    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  defp compile_plan do
    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      media_policy: %{transcript_routes: %{}, save_transcripts: false},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human_participant(%{speech_to_text: "plan-stt"}),
        "receiver" => human_participant(%{})
      },
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

  defp attach(plan, room, caller) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "conn-stt-policy",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} = CallEngine.attach_connection(command)
    attachment
  end

  defp audio_frame(plan, room, caller) do
    %AudioFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: caller.participant_id,
      connection_id: "conn-stt-policy",
      track_id: "track-stt-policy",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 960,
      payload: <<1>>,
      received_at: System.monotonic_time(:millisecond)
    }
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
