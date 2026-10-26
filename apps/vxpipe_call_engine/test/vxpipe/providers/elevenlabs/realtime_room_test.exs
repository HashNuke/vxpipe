defmodule Vxpipe.Providers.ElevenLabs.RealtimeRoomTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTenantCredentialSource}
  alias Vxpipe.CallEngine.{TestElevenLabsRealtimeAPI, TestTransferConnection}
  alias Vxpipe.CallEngine.TestElevenLabsRealtimeRoomPing
  alias Vxpipe.CallEngine.TestElevenLabsRealtimeTransport, as: Wire
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech, as: STSCapability
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    ParticipantTranscription,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority
  alias Vxpipe.CallEngine.MediaPolicy.Enforcer
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech, as: RoomSpeechToSpeech

  alias Vxpipe.CallEngine.Speech.{
    ActivityRuntime,
    ActivitySupervisor,
    ConversationalSTT,
    Session
  }

  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeSession}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    settings =
      original
      |> Keyword.put(:speech_to_text, providers: %{})
      |> Keyword.put(:text_to_speech, providers: %{})
      |> Keyword.put(:speech_to_speech, providers: %{RealtimeSession => [enabled: true]})

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  test "native room turns complete a tool-only ping before credited speech without local VAD" do
    context = start_room()
    %{wire: wire, sink: sink, capability: capability, caller: caller, agent: agent} = context
    pcm = :binary.copy(<<1_000::signed-little-16>>, 480)

    assert :ok =
             TestTransferConnection.run(context.command, fn ->
               CallEngine.push_speech_to_speech_audio(context.attachment, frame(context, pcm))
             end)

    assert_receive {:realtime_sent, ^wire,
                    %{"type" => "input_audio_buffer.append", "audio" => encoded}},
                   1_000

    assert Base.decode64!(encoded) == pcm
    deliver(context, %{"type" => "input_audio_buffer.speech_started", "item_id" => "caller_1"})
    deliver(context, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "caller_1"})

    # Native response.created has no metadata and can precede the caller's final transcript.
    deliver(context, %{"type" => "response.created", "response" => %{"id" => "response_1"}})

    deliver(context, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "caller_1",
      "transcript" => "Hello"
    })

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{participant_id: ^caller, text: "Hello", final: true}},
                   1_000

    refute_received {:realtime_sent, ^wire, %{"type" => "response.create"}}

    deliver(context, %{
      "type" => "response.function_call_arguments.done",
      "response_id" => "response_1",
      "call_id" => "call_ping",
      "name" => "ping",
      "arguments" => "{}"
    })

    assert_receive {:vxpipe_event,
                    %ToolCallStarted{
                      name: "ping",
                      participant_id: ^agent,
                      source_participant_id: ^agent
                    } = tool},
                   1_000

    assert_receive {:vxpipe_event, %ToolCallCompleted{result: %{"pong" => true}} = completed},
                   1_000

    assert completed.tool_call_id == tool.tool_call_id
    assert completed.correlation_id == tool.correlation_id
    assert tool.connection_id == context.command.connection_id

    assert_receive {:realtime_sent, ^wire,
                    %{
                      "type" => "conversation.item.create",
                      "item" => %{
                        "type" => "function_call_output",
                        "call_id" => "call_ping",
                        "output" => result
                      }
                    }},
                   1_000

    assert JSON.decode!(result) == %{"pong" => true}
    assert :sys.get_state(capability).active_output == nil

    deliver(context, %{
      "type" => "response.done",
      "response" => %{"id" => "response_1", "status" => "completed"}
    })

    assert_receive {:realtime_sent, ^wire, %{"type" => "response.create"}}, 1_000
    assert :sys.get_state(capability).active_output == nil
    refute_received {:test_audio_output, ^sink, _}
    refute_received {:test_audio_output_finish, ^sink, _}
    refute_received {:vxpipe_event, %AgentSpeechStarted{}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{}}
    refute_received {:vxpipe_event, %TextOutput{}}

    deliver(context, %{"type" => "response.created", "response" => %{"id" => "response_2"}})
    deliver(context, audio(pcm))
    assert_receive {:test_audio_output, ^sink, first}, 1_000
    assert first.sample_rate == 48_000
    assert first.payload == :binary.copy(<<1_000::signed-little-16>>, 960)

    # The sink withholds the first delivery credit while the provider finishes generation.
    deliver(context, audio(pcm))

    deliver(context, %{
      "type" => "response.output_audio_transcript.done",
      "response_id" => "response_2",
      "transcript" => "Hello there"
    })

    deliver(context, %{
      "type" => "response.done",
      "response" => %{"id" => "response_2", "status" => "completed"}
    })

    refute :sys.get_state(capability).active_output.generation_done?
    refute_received {:test_audio_output, ^sink, _}
    refute_received {:test_audio_output_finish, ^sink, _}
    refute_received {:vxpipe_event, %TextOutput{}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{}}

    assert :ok = GenServer.call(sink, {:complete_output, :ok})
    assert_receive {:test_audio_output, ^sink, second}, 1_000
    assert second.payload == first.payload
    assert second.correlation_id == first.correlation_id
    assert_receive {:test_audio_output_finish, ^sink, _turn}, 1_000
    refute_received {:vxpipe_event, %TextOutput{}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{}}

    assert :ok = TestAudioOutputSink.playback_progress(sink, 40, 40)
    assert :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^agent,
                      text: "Hello there",
                      will_be_spoken: true
                    }},
                   1_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: ^agent}}, 1_000
    refute_received {:vxpipe_event, %TextOutput{}}
    assert_no_local_vad(context)
  end

  test "room hold closes admitted native input before release and delayed caller evidence without new PCM" do
    context = start_uncertain_room()

    :sys.replace_state(context.authority, &RoomSpeechToSpeech.hold/1)
    assert_allocation_closed(context)

    :sys.replace_state(context.authority, &RoomSpeechToSpeech.release/1)
    assert_retired_evidence_ignored(context)
  end

  test "policy revoke closes admitted native input before regrant and delayed caller evidence without new PCM" do
    context = start_uncertain_room()
    policy = :sys.get_state(context.authority).media_policy_authority

    assert {:ok, absent} = MediaPolicyAuthority.leave(policy, context.agent)
    refute MapSet.member?(absent.present_participant_ids, context.agent)
    assert_allocation_closed(context)

    assert {:ok, restored} = MediaPolicyAuthority.admit(policy, context.agent)
    assert MapSet.member?(restored.present_participant_ids, context.agent)
    assert_retired_evidence_ignored(context)
  end

  test "direct policy API closes admitted native input before delayed caller evidence" do
    context = start_uncertain_room()
    policy = :sys.get_state(context.capability).policy

    # This API supplies no interval proof, even when its effective policy is unchanged.
    assert {:error, :unavailable} = STSCapability.apply_policy(context.capability, policy)
    assert_allocation_closed(context)
    assert_retired_evidence_ignored(context)
  end

  test "an unrelated snapshot revision preserves native input allocation and caller evidence" do
    context = start_uncertain_room()
    %{wire: wire, caller: caller, capability: capability} = context
    before = :sys.get_state(capability)
    snapshot = %{before.input_policy | revision: before.input_policy.revision + 1}

    assert :ok = Enforcer.apply(capability, snapshot, 1_000)
    after_policy = :sys.get_state(capability)
    assert after_policy.policy_revision == snapshot.revision
    assert after_policy.input_policy.intervals == before.input_policy.intervals

    assert after_policy.input_policy.present_participant_ids ==
             before.input_policy.present_participant_ids

    assert after_policy.session == before.session
    assert after_policy.input_epoch == before.input_epoch
    assert after_policy.response_origins == before.response_origins
    assert Session.provider(after_policy.session) == context.provider

    deliver(context, %{"type" => "input_audio_buffer.speech_started", "item_id" => "same_origin"})
    deliver(context, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "same_origin"})

    deliver(context, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "same_origin",
      "transcript" => "Still the same caller"
    })

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: ^caller,
                      text: "Still the same caller",
                      final: true
                    }},
                   1_000

    for {pid, monitor} <- context.allocation_monitors do
      refute_received {:DOWN, ^monitor, :process, ^pid, _reason}
    end

    refute_received {:realtime_wire, _replacement}
    refute_received {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}
    assert_no_local_vad(context)
  end

  test "direct release with a new epoch closes admitted native input without a preceding hold" do
    context = start_uncertain_room()

    _ = STSCapability.release(context.capability, make_ref())
    assert_allocation_closed(context)
    assert_retired_evidence_ignored(context)
  end

  test "repeated release of the same epoch preserves the lifecycle and continues native input" do
    context = start_uncertain_room()
    %{wire: wire, capability: capability, caller: caller} = context
    before = :sys.get_state(capability)

    assert :ok = STSCapability.release(capability, before.input_epoch)
    assert :ok = STSCapability.release(capability, before.input_epoch)
    after_release = :sys.get_state(capability)
    assert after_release.origin_lifecycle_revision == before.origin_lifecycle_revision
    assert after_release.input_epoch == before.input_epoch
    assert after_release.session == before.session
    assert after_release.response_origins == before.response_origins

    next_frame = %{frame(context, context.pcm) | sequence_number: 1, timestamp: 480}

    assert :ok =
             TestTransferConnection.run(context.command, fn ->
               CallEngine.push_speech_to_speech_audio(context.attachment, next_frame)
             end)

    assert_receive {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}, 1_000
    deliver(context, %{"type" => "input_audio_buffer.speech_started", "item_id" => "same_epoch"})
    deliver(context, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "same_epoch"})

    deliver(context, %{
      "type" => "conversation.item.input_audio_transcription.completed",
      "item_id" => "same_epoch",
      "transcript" => "The epoch is unchanged"
    })

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: ^caller,
                      text: "The epoch is unchanged",
                      final: true
                    }},
                   1_000

    assert :sys.get_state(capability).response_origins == before.response_origins
    assert_no_local_vad(context)
  end

  for boundary <- [:hold, :direct_policy, :snapshot] do
    test "#{boundary} clears buffered audio in the independent sink before closing the allocation" do
      context = start_uncertain_room()
      %{wire: wire, capability: capability, sink: sink} = context
      deliver(context, %{"type" => "input_audio_buffer.speech_started", "item_id" => "buffered"})
      deliver(context, %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "buffered"})

      deliver(context, %{
        "type" => "conversation.item.input_audio_transcription.completed",
        "item_id" => "buffered",
        "transcript" => "Please answer"
      })

      deliver(context, %{"type" => "response.created", "response" => %{"id" => "response_2"}})
      deliver(context, audio(context.pcm))
      assert_receive {:test_audio_output, ^sink, first}, 1_000
      deliver(context, audio(context.pcm))
      assert :sys.get_state(sink).pending_output != nil
      assert :sys.get_state(sink).callback == {capability, first.correlation_id}
      state = :sys.get_state(capability)

      case unquote(boundary) do
        :hold ->
          _ = STSCapability.hold(capability)

        :direct_policy ->
          _ = STSCapability.apply_policy(capability, state.policy)

        :snapshot ->
          snapshot = %{
            state.input_policy
            | revision: state.input_policy.revision + 1,
              present_participant_ids:
                MapSet.delete(state.input_policy.present_participant_ids, context.agent)
          }

          _ = Enforcer.apply(capability, snapshot, 1_000)
      end

      turn = first.correlation_id
      assert_receive {:test_audio_output_interrupt, ^sink, ^turn, 0}, 1_000
      assert :sys.get_state(sink).pending_output == nil
      assert :sys.get_state(sink).callback == nil
      assert_allocation_closed(context)
      refute_received {:test_audio_output, ^sink, _}
      refute_received {:test_audio_output_finish, ^sink, _}
      refute_received {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}
    end
  end

  defp start_uncertain_room do
    context = start_room()
    wire = context.wire
    pcm = :binary.copy(<<1_000::signed-little-16>>, 480)

    assert :ok =
             TestTransferConnection.run(context.command, fn ->
               CallEngine.push_speech_to_speech_audio(context.attachment, frame(context, pcm))
             end)

    assert_receive {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}, 1_000
    allocation = :sys.get_state(context.capability).session
    refute Session.input_quiescent?(allocation)
    assert_no_local_vad(context)

    monitors =
      Enum.map(
        [context.provider, Session.tree(allocation), wire, context.capability],
        fn pid -> {pid, Process.monitor(pid)} end
      )

    Map.merge(context, %{allocation_monitors: monitors, pcm: pcm})
  end

  defp assert_allocation_closed(context) do
    for {pid, monitor} <- context.allocation_monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end
  end

  defp assert_retired_evidence_ignored(context) do
    %{wire: wire, sink: sink} = context

    # Model socket messages already in flight to the retired provider. No fresh
    # microphone input may be needed to close the old authorization origin.
    for message <- [
          %{"type" => "input_audio_buffer.speech_started", "item_id" => "delayed_old_caller"},
          %{"type" => "input_audio_buffer.speech_stopped", "item_id" => "delayed_old_caller"},
          %{
            "type" => "conversation.item.input_audio_transcription.completed",
            "item_id" => "delayed_old_caller",
            "transcript" => "Retired caller input"
          },
          %{"type" => "response.created", "response" => %{"id" => "response_2"}},
          audio(context.pcm)
        ] do
      send(context.provider, {:elevenlabs_realtime, wire, JSON.encode!(message)})
    end

    _ = :sys.get_state(context.authority)
    _ = TestTransferConnection.attachment(context.command)

    refute_received {:realtime_sent, ^wire, %{"type" => "input_audio_buffer.append"}}
    refute_received {:test_audio_output, ^sink, _}
    refute_received {:test_audio_output_finish, ^sink, _}
    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_received {:vxpipe_event, %ParticipantTranscription{}}
    refute_received {:vxpipe_event, %AgentSpeechStarted{}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{}}
    refute_received {:vxpipe_event, %TextOutput{}}
  end

  defp start_room do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self(), block_output: true})

    bindings = %{
      {plan.tenant_id, "elevenlabs", "default"} => %{"api_key" => "synthetic-room-key"}
    }

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               credential_source: {TestTenantCredentialSource, {self(), bindings}}
             )

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    [{room_tree, _}] =
      Registry.lookup(
        CallEngine.RoomRegistry,
        {:room_incarnation, plan.tenant_id, plan.room_id, room.incarnation_id}
      )

    on_exit(fn -> DynamicSupervisor.terminate_child(CallEngine.RoomSupervisor, room_tree) end)
    observer = self()

    # Preserve the compiled provider, credentials, prompt and options. Only replace private I/O.
    state =
      :sys.replace_state(authority, fn state ->
        runtime = state.speech_to_speech_runtime

        private =
          Keyword.merge(runtime.provider_private,
            api_module: TestElevenLabsRealtimeAPI,
            wire_module: Wire,
            wire_options: [observer: observer]
          )

        %{state | speech_to_speech_runtime: %{runtime | provider_private: private}}
      end)

    assert {RealtimeSession, public} = state.speech_to_speech_runtime.provider
    assert Keyword.fetch!(public, :turn_control) == "provider"
    config = Keyword.fetch!(state.speech_to_speech_runtime.provider_private, :config)
    native = Realtime.session(config)

    assert get_in(native, ["audio", "input", "turn_detection"]) == %{
             "type" => "semantic_vad",
             "create_response" => true,
             "interrupt_response" => false
           }

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "realtime-room-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    track = %{track_id: "microphone", codec: :linear16, sample_rate: 24_000, channels: 1}
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink, input_track: track)
    assert_receive {:realtime_wire, wire}, 5_000
    assert :ok = Wire.deliver(wire, %{"type" => "session.created", "session" => native})
    TestCallStartup.await_ready(plan.room_id)
    attachment = TestTransferConnection.attachment(command)
    assert attachment.media_ingress == nil

    assert {:ok, %{format: format}} = CallEngine.speech_to_speech_input_configuration(attachment)
    assert format == Map.delete(track, :track_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    context = %{
      authority: authority,
      room_tree: room_tree,
      capability: capability,
      provider: Session.provider(:sys.get_state(capability).session),
      command: command,
      attachment: attachment,
      caller: caller.participant_id,
      agent: agent.participant_id,
      sink: sink,
      wire: wire
    }

    assert_no_local_vad(context)
    context
  end

  defp assert_no_local_vad(context) do
    state = :sys.get_state(context.authority)
    assert Enum.all?(state.speech_to_text_runtime, fn {_key, runtime} -> is_nil(runtime) end)
    assert state.speech_to_speech_runtime.output_speech_to_text == nil
    assert :sys.get_state(context.capability).provider == RealtimeSession
    modules = supervised_modules(context.room_tree)
    refute ActivitySupervisor in modules
    refute ActivityRuntime in modules
    refute ConversationalSTT in modules
  end

  defp supervised_modules(supervisor) do
    Enum.flat_map(Supervisor.which_children(supervisor), fn {_id, pid, type, modules} ->
      own = if is_list(modules), do: modules, else: []
      if type == :supervisor and is_pid(pid), do: own ++ supervised_modules(pid), else: own
    end)
  end

  defp deliver(context, message) do
    assert :ok = Wire.deliver(context.wire, message)
    _ = :sys.get_state(context.provider)
    _ = :sys.get_state(context.capability)
    _ = :sys.get_state(context.authority)
  end

  defp audio(pcm) do
    %{
      "type" => "response.output_audio.delta",
      "response_id" => "response_2",
      "delta" => Base.encode64(pcm)
    }
  end

  defp frame(context, pcm) do
    command = context.command

    %AudioFrame{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      track_id: "microphone",
      codec: :linear16,
      sample_rate: 24_000,
      channels: 1,
      sequence_number: 0,
      timestamp: 0,
      payload: pcm,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp compile_plan do
    source = %{
      schema_version: "20260915.01",
      wait_sounds: nil,
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{"ping" => %{type: "host", tool: "ping"}},
          transfers: [],
          capabilities: %{
            speech_to_speech: %{provider: "elevenlabs", model: "eleven_realtime_v1_mini"}
          }
        }
      }
    }

    assert {:ok, spec} =
             CallSpec.new(source, resource_id: "elevenlabs-realtime-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: spec.resource_id, revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-elevenlabs-realtime-room",
               actor_id: "actor-elevenlabs-realtime-room"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(spec, invocation, %{
               host_tools: %{"ping" => TestElevenLabsRealtimeRoomPing}
             })

    plan
  end
end
