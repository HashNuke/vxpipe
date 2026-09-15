defmodule Vxpipe.CallEngine.DefinitionDrivenCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff}
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallDefinition,
    CallInvocation,
    CallVariables,
    ConnectionAttachment,
    DefinitionCompiler,
    Error,
    PlanStartup,
    RoomAuthority,
    RoomMixer,
    TranscriptRouter
  }

  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Diagnostics.{AgentRuntimeModelProvider, ModelFixture}
  alias Vxpipe.CallEngine.LiveInspection.Buffer, as: LiveInspectionBuffer
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Snapshot}

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
    JoinParticipant,
    ReadCallVariables,
    SendText,
    UpdateCallVariables
  }

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnFailed,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Tool.CurrentTime
  alias Vxpipe.CallEngine.Provider.{MorseCodeSTT, MorseCodeTTS}
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.Provider.MorseCode.Config, as: MorseConfig
  alias Vxpipe.CallEngine.Usage.{ProviderContext, TelephonyAttempt}

  alias Vxpipe.CallEngine.{
    TestAudioOutputSink,
    TestAgentRuntimeModelProvider,
    TestArchiveWriter,
    TestCollectingArchiveWriter,
    TestFailingTextToSpeechTransport,
    TestRecoveringArchiveWriter,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport
  }

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}

  test "archives private lifecycle, accepted input, tool, and generated-output facts" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-private-history")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 64
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    attach_caller(plan, room, caller, "conn-private-history")

    command =
      send_command(
        plan,
        room,
        caller,
        "conn-private-history",
        "What time is it?"
      )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)

    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:ok, call} =
             ToolCall.new(
               id: "tool-private-history",
               name: "get_current_time",
               arguments: %{}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement_request}
    assert acknowledgement_request.tools == []
    assert {:ok, response} = ModelResponse.new(text: "The host action started.")
    send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    assert {:ok, response} = ModelResponse.new(text: "The host action completed.")
    send(completion_provider, {:test_agent_runtime_response, {:ok, response}})

    facts = collect_archive_facts_through(:agent_turn_completed, 2)

    assert Enum.map(facts, & &1.sequence) == Enum.to_list(1..length(facts))

    assert %Fact{kind: :room_opened, call_id: call_id} = fact!(facts, :room_opened)
    assert call_id == plan.call_id

    assert Enum.any?(facts, fn
             %Fact{
               kind: :participant_joined,
               participant_id: participant_id,
               payload: %{"role" => "human"}
             } ->
               participant_id == caller.participant_id

             _other ->
               false
           end)

    assert Enum.any?(facts, fn
             %Fact{
               kind: :participant_joined,
               participant_id: participant_id,
               activation_id: activation_id,
               payload: %{"role" => "agent"}
             } ->
               participant_id == receiver.participant_id and
                 activation_id == receiver.activation_id

             _other ->
               false
           end)

    assert %Fact{
             kind: :connection_attached,
             participant_id: caller_participant_id,
             connection_id: "conn-private-history"
           } = fact!(facts, :connection_attached)

    assert caller_participant_id == caller.participant_id

    assert %Fact{
             kind: :participant_turn_started,
             command_id: command_id,
             correlation_id: correlation_id,
             public_sequence: 1,
             payload: %{"modality" => "text"}
           } = fact!(facts, :participant_turn_started)

    assert command_id == command.id
    assert correlation_id == command.correlation_id

    assert %Fact{
             kind: :accepted_input,
             participant_id: caller_participant_id,
             command_id: command_id,
             correlation_id: correlation_id,
             public_sequence: nil,
             payload: %{"content" => "What time is it?", "modality" => "text"}
           } = fact!(facts, :accepted_input)

    assert caller_participant_id == caller.participant_id
    assert command_id == command.id
    assert correlation_id == command.correlation_id

    assert %Fact{
             kind: :participant_turn_completed,
             public_sequence: 2,
             payload: %{"modality" => "text"}
           } = fact!(facts, :participant_turn_completed)

    assert %Fact{
             kind: :tool_call_started,
             participant_id: agent_participant_id,
             source_participant_id: source_participant_id,
             tool_call_id: "tool-private-history",
             public_sequence: 3,
             payload: %{"arguments" => %{}, "name" => "get_current_time"}
           } = fact!(facts, :tool_call_started)

    assert agent_participant_id == receiver.participant_id
    assert source_participant_id == caller.participant_id

    assert %Fact{
             kind: :tool_call_completed,
             tool_call_id: "tool-private-history",
             public_sequence: 4,
             payload: %{
               "name" => "get_current_time",
               "result" => %{"timezone" => "UTC"}
             }
           } = fact!(facts, :tool_call_completed)

    tool_usage =
      Enum.filter(facts, fn
        %Fact{kind: :usage_observed, payload: %{"capability" => "tool"}} -> true
        _other -> false
      end)

    assert [started_usage, completed_usage] = tool_usage
    assert started_usage.payload["outcome"] == "in_progress"
    assert started_usage.payload["provider"] == %{"name" => "host_application"}

    assert started_usage.payload["measurement"] == %{
             "component" => "invocations",
             "mode" => "delta",
             "provenance" => "locally_measured",
             "quantity" => 1,
             "status" => "final",
             "unit" => "requests"
           }

    assert completed_usage.payload["outcome"] == "succeeded"
    refute Map.has_key?(completed_usage.payload, "measurement")

    assert Enum.all?(tool_usage, fn fact ->
             fact.tenant_id == plan.tenant_id and
               fact.call_id == plan.call_id and
               fact.room_id == plan.room_id and
               fact.incarnation_id == room.incarnation_id and
               fact.participant_id == receiver.participant_id and
               fact.activation_id == receiver.activation_id and
               fact.correlation_id == command.correlation_id and
               fact.tool_call_id == "tool-private-history" and
               fact.public_sequence == nil
           end)

    assert %Fact{
             kind: :agent_output_generated,
             public_sequence: 5,
             payload: %{
               "aggregated_by" => "sentence",
               "text" => "The host action started.",
               "will_be_spoken" => false
             }
           } = fact!(facts, :agent_output_generated)

    assert %Fact{kind: :agent_turn_completed, public_sequence: 6} =
             fact!(facts, :agent_turn_completed)

    assert Enum.any?(facts, fn
             %Fact{
               kind: :agent_output_generated,
               public_sequence: 7,
               payload: %{"text" => "The host action completed."}
             } ->
               true

             _other ->
               false
           end)

    assert Enum.any?(facts, &match?(%Fact{kind: :agent_turn_completed, public_sequence: 8}, &1))
    refute_receive {:vxpipe_event, %{kind: :usage_observed}}
  end

  test "archives final audio input and distinguishes generated from delivered output" do
    configure_agent_runtime_provider(self())
    configure_speech_runtime()
    room_id = unique_id("room-private-audio-history")
    plan = compile_plan(room_id, speech?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 64
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    assert_receive {:test_tts_transport_started, tts_transport, _connection}
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    assert {:ok, %ConnectionAttachment{}} =
             attach_caller(plan, room, caller, "conn-private-audio-history", sink)

    assert_receive {:test_stt_transport_started, stt_transport, _connection}

    TestSpeechToTextTransport.deliver(
      stt_transport,
      stt_turn_message("StartOfTurn", 1, "Hello")
    )

    TestSpeechToTextTransport.deliver(
      stt_transport,
      stt_turn_message("EndOfTurn", 2, "Hello there", "model")
    )

    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).content == "Hello there"
    assert {:ok, response} = ModelResponse.new(text: "Hello back.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_tts_control, ^tts_transport, speak}, 2_000
    assert JSON.decode!(speak) == %{"text" => "Hello back.", "type" => "Speak"}
    assert_receive {:test_tts_control, ^tts_transport, _flush}, 2_000

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"speech-private"})
    )

    TestTextToSpeechTransport.deliver_audio(tts_transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}, 2_000

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"speech-private"})
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn_id}, 2_000
    :ok = TestAudioOutputSink.playback_started(sink)
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    :ok = TestAudioOutputSink.playback_completed(sink)

    facts = collect_archive_facts_through(:agent_turn_completed)

    refute Enum.any?(facts, &(&1.kind == :participant_transcription_partial))

    assert %Fact{
             kind: :participant_transcription_final,
             participant_id: participant_id,
             payload: %{
               "final" => true,
               "provider_turn_index" => 0,
               "text" => "Hello there"
             }
           } = fact!(facts, :participant_transcription_final)

    assert participant_id == caller.participant_id

    assert %Fact{
             kind: :accepted_input,
             payload: %{"content" => "Hello there", "modality" => "audio"}
           } = fact!(facts, :accepted_input)

    stt_usage =
      Enum.filter(facts, fn
        %Fact{kind: :usage_observed, payload: %{"capability" => "speech_to_text"}} -> true
        _other -> false
      end)

    assert stt_usage
           |> Enum.reject(&(Map.get(&1.payload, "measurement") == nil))
           |> Enum.map(&get_in(&1.payload, ["measurement", "component"]))
           |> Enum.sort() == ["recognized_audio_duration", "recognized_text_characters"]

    assert Enum.any?(stt_usage, fn fact ->
             fact.payload["outcome"] == "in_progress" and
               Map.get(fact.payload, "measurement") == nil
           end)

    assert Enum.all?(stt_usage, fn fact ->
             fact.tenant_id == plan.tenant_id and
               fact.call_id == plan.call_id and
               fact.room_id == plan.room_id and
               fact.incarnation_id == room.incarnation_id and
               fact.participant_id == caller.participant_id and
               fact.activation_id == caller.activation_id and
               fact.payload["provider"]["name"] == "deepgram" and
               fact.payload["provider"]["integration_id"] ==
                 Vxpipe.CallEngine.CallDefinition.CapabilitySelection.identity(
                   caller.capabilities.speech_to_text,
                   plan.tenant_id
                 ) and
               fact.payload["provider"]["request_id"] == "request-private-history" and
               is_binary(fact.payload["attribution"]["service_interval_id"])
           end)

    generated = fact!(facts, :agent_output_generated)

    assert %Fact{
             kind: :agent_output_generated,
             payload: %{"text" => "Hello back.", "will_be_spoken" => true}
           } = generated

    assert %Fact{
             kind: :agent_output_delivery_started,
             payload: %{"output_id" => output_id, "text" => "Hello back."}
           } = fact!(facts, :agent_output_delivery_started)

    assert output_id == generated.id

    assert %Fact{
             kind: :agent_output_delivery_progressed,
             payload: %{
               "output_id" => ^output_id,
               "played_ms" => 20,
               "text" => "Hello back.",
               "total_ms" => 100
             }
           } = fact!(facts, :agent_output_delivery_progressed)

    assert %Fact{
             kind: :agent_output_delivered,
             public_sequence: nil,
             payload: %{"output_id" => ^output_id, "text" => "Hello back."}
           } = fact!(facts, :agent_output_delivered)

    tts_usage =
      Enum.filter(facts, fn
        %Fact{kind: :usage_observed, payload: %{"capability" => "text_to_speech"}} -> true
        _other -> false
      end)

    assert Enum.map(tts_usage, &get_in(&1.payload, ["measurement", "component"]))
           |> Enum.sort() == ["generated_audio_duration", "input_characters"]

    assert Enum.all?(tts_usage, fn fact ->
             fact.tenant_id == plan.tenant_id and
               fact.call_id == plan.call_id and
               fact.room_id == plan.room_id and
               fact.incarnation_id == room.incarnation_id and
               fact.participant_id == receiver.participant_id and
               fact.activation_id == receiver.activation_id and
               fact.payload["provider"]["name"] == "deepgram" and
               fact.payload["provider"]["integration_id"] ==
                 Vxpipe.CallEngine.CallDefinition.CapabilitySelection.identity(
                   receiver.capabilities.text_to_speech,
                   plan.tenant_id
                 ) and
               fact.payload["provider"]["request_id"] == "req" and
               fact.payload["provider"]["operation_id"] == "speech-private"
           end)
  end

  test "applies a present participant's transcript routes and storage denial" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-transcript-policy")

    transform = fn input ->
      put_in(input, [:participants, "unused-agent", :while_present], %{
        transcript_routes: %{"receiver" => []},
        save_transcripts: false
      })
    end

    plan = compile_plan(room_id, definition_transform: transform)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    restricted = Map.fetch!(plan.participants, "unused-agent")

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 32
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    attach_caller(plan, room, caller, "conn-transcript-policy")

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: restricted.participant_id,
               role: :agent,
               deadline: future_deadline()
             )

    assert {:ok, _participant} = CallEngine.join_participant(join)

    command =
      send_command(
        plan,
        room,
        caller,
        "conn-transcript-policy",
        "Do not archive this text."
      )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    assert {:ok, response} = ModelResponse.new(text: "This output is private.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    refute_receive {:vxpipe_event, %TextOutput{text: "This output is private."}}

    facts = collect_archive_facts_through(:agent_turn_completed)

    assert %Fact{
             kind: :accepted_input,
             source_policy: %{
               "media_policy_revision" => 3,
               "save_transcripts" => false
             },
             payload: %{"modality" => "text"}
           } = fact!(facts, :accepted_input)

    assert %Fact{
             kind: :agent_output_generated,
             source_policy: %{
               "media_policy_revision" => 3,
               "save_transcripts" => false
             },
             payload: %{"aggregated_by" => "sentence", "will_be_spoken" => false}
           } = fact!(facts, :agent_output_generated)
  end

  test "archives authoritative connection and participant departures" do
    room_id = unique_id("room-private-departures")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 32
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    attach_caller(plan, room, caller, "conn-private-departures")
    _startup_facts = collect_archive_facts_through(:connection_attached)

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    assert {:ok, detach} =
             AttachConnection.new(
               id: "cmd-detach-private-history",
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "conn-private-departures",
               deadline: future_deadline()
             )

    assert :ok =
             Vxpipe.CallEngine.TestTransferConnection.run(detach, fn ->
               RoomAuthority.detach_connection(room_authority, detach, self())
             end)

    assert %Snapshot{revision: 2, present_participant_ids: present_after_disconnect} =
             Authority.snapshot(Authority.whereis(room.incarnation_id))

    assert present_after_disconnect ==
             MapSet.new([caller.participant_id, receiver.participant_id])

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :connection_detached,
                      participant_id: participant_id,
                      connection_id: "conn-private-departures",
                      command_id: "cmd-detach-private-history"
                    }}

    assert participant_id == caller.participant_id

    assert [{participant_authority, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:participant, plan.tenant_id, room_id, caller.participant_id}
             )

    Process.exit(participant_authority, :kill)

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :participant_left,
                      participant_id: participant_id,
                      activation_id: nil
                    }},
                   2_000

    assert participant_id == caller.participant_id

    assert %Snapshot{revision: 3, present_participant_ids: present_after_leave} =
             Authority.snapshot(Authority.whereis(room.incarnation_id))

    assert present_after_leave == MapSet.new([receiver.participant_id])
  end

  test "keeps tools and variables live while archival crashes, then drains retained facts" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-archive-recovery")
    plan = compile_variables_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    writer =
      start_supervised!({TestRecoveringArchiveWriter, mode: :raise, observer: self()})

    archive =
      archive_options(
        writer: {TestRecoveringArchiveWriter, writer},
        maximum_pending_facts: 64,
        retry_delay_ms: 5
      )

    assert {:ok, handoff} = ArchiveSupervisor.open(archive)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive_handoff: handoff
             )

    assert_receive {:test_archive_attempt, _first_retained, :raise}, 1_000
    assert_receive {:test_archive_attempt, _retried_retained, :raise}, 1_000
    attach_caller(plan, room, caller, "conn-archive-recovery")

    command =
      send_command(
        plan,
        room,
        caller,
        "conn-archive-recovery",
        "Can you check the time?"
      )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)

    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:ok, call} =
             ToolCall.new(
               id: "tool-during-archive-outage",
               name: "get_current_time",
               arguments: %{}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{tool_call_id: "tool-during-archive-outage"}},
                   2_000

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement_request}
    assert acknowledgement_request.tools == []
    assert {:ok, response} = ModelResponse.new(text: "The tool is running.")
    send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    assert {:ok, response} = ModelResponse.new(text: "The tool still completed.")
    send(completion_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %TextOutput{text: "The tool still completed."}}, 2_000
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 2_000

    variables = CallVariables.whereis(room.incarnation_id)

    assert {:ok, update} =
             UpdateCallVariables.new(
               tenant_id: plan.tenant_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: receiver.participant_id,
               activation_id: receiver.activation_id,
               source_participant_id: caller.participant_id,
               correlation_id: command.correlation_id,
               tool_call_id: "tool-variable-during-archive-outage",
               section: "intake",
               expected_revision: 0,
               operation: {:put, "summary", "accepted locally"},
               deadline: future_deadline()
             )

    assert {:ok, %{"global_revision" => 1, "revision" => 1}} =
             CallVariables.update(variables, update)

    assert {:ok, read} =
             ReadCallVariables.new(
               tenant_id: plan.tenant_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: receiver.participant_id,
               sections: ["intake"],
               deadline: future_deadline()
             )

    assert {:ok,
            %{
              "sections" => %{
                "intake" => %{"value" => %{"summary" => "accepted locally"}}
              }
            }} = CallVariables.read(variables, read)

    assert {:ok, inspection_port} =
             LiveInspectionBuffer.port(plan.tenant_id, plan.call_id)

    _ = :sys.get_state(inspection_port.buffer)

    assert {:ok, live_inspection} =
             CallEngine.inspect_live_call(plan.tenant_id, plan.call_id)

    assert live_inspection.latest_variable_revision == 1

    assert Enum.any?(live_inspection.records, fn
             %Fact{
               kind: :tool_call_completed,
               correlation_id: correlation_id,
               tool_call_id: "tool-during-archive-outage"
             } ->
               correlation_id == command.correlation_id

             _record ->
               false
           end)

    assert Enum.any?(live_inspection.records, fn
             %UpdateSnapshot{
               participant_id: participant_id,
               correlation_id: correlation_id,
               global_revision: 1
             } ->
               participant_id == receiver.participant_id and
                 correlation_id == command.correlation_id

             _record ->
               false
           end)

    assert %{pending: pending, retries: retries} = Handoff.stats(handoff)
    assert pending > 0
    assert retries > 0

    TestRecoveringArchiveWriter.recover(writer)

    assert [{authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    subscriber_monitor = Process.monitor(handoff.subscriber)
    GenServer.stop(authority)
    assert_receive {:DOWN, ^subscriber_monitor, :process, _subscriber, :normal}, 2_000
    assert %{pending: 0} = Handoff.stats(handoff)

    archived = TestRecoveringArchiveWriter.facts(writer)
    ids = Enum.map(archived, & &1.id)

    assert length(ids) == length(Enum.uniq(ids))
    assert Enum.any?(archived, &match?(%BaselineSnapshot{}, &1))
    assert Enum.any?(archived, &match?(%UpdateSnapshot{global_revision: 1}, &1))
    assert Enum.any?(archived, &match?(%Fact{kind: :accepted_input}, &1))
    assert Enum.any?(archived, &match?(%Fact{kind: :tool_call_completed}, &1))
    assert Enum.any?(archived, &match?(%Fact{kind: :archive_stream_closed}, &1))
  end

  test "archives model usage privately with call and turn attribution" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-model-usage")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 32
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    attach_caller(plan, room, caller, "conn-model-usage")
    _startup_facts = collect_archive_facts_through(:connection_attached)

    command =
      send_command(
        plan,
        room,
        caller,
        "conn-model-usage",
        "Please answer this measured turn"
      )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)
    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:ok, response} =
             ModelResponse.new(
               text: "Measured answer.",
               usage: %{input_tokens: 8, output_tokens: 2, total_tokens: 10},
               provider_metadata: %{
                 request_id: "provider-request-room-1",
                 response_id: "provider-response-room-1",
                 authorization: "must-not-be-archived"
               }
             )

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    facts = collect_archive_facts_through(:usage_observed, 3)
    usage_facts = Enum.filter(facts, &(&1.kind == :usage_observed))

    assert Enum.map(usage_facts, &get_in(&1.payload, ["measurement", "component"]))
           |> Enum.sort() == ["input_tokens", "output_tokens", "total_tokens"]

    assert Enum.all?(usage_facts, fn fact ->
             fact.tenant_id == plan.tenant_id and
               fact.call_id == plan.call_id and
               fact.room_id == room_id and
               fact.incarnation_id == room.incarnation_id and
               fact.participant_id == receiver.participant_id and
               fact.activation_id == receiver.activation_id and
               fact.correlation_id == command.correlation_id and
               fact.public_sequence == nil and
               fact.payload["provider"]["name"] == "test" and
               fact.payload["provider"]["integration_id"] ==
                 Vxpipe.CallEngine.CallDefinition.CapabilitySelection.identity(
                   receiver.capabilities.model_inference,
                   plan.tenant_id
                 ) and
               fact.payload["provider"]["request_id"] == "provider-request-room-1" and
               fact.payload["provider"]["operation_id"] == "provider-response-room-1"
           end)

    refute inspect(usage_facts) =~ "must-not-be-archived"
    refute_receive {:vxpipe_event, %{kind: :usage_observed}}
  end

  test "archives trusted telephony usage privately for the exact live room" do
    room_id = unique_id("room-telephony-usage")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 16
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    assert {:ok, provider} =
             ProviderContext.new(
               name: "telnyx",
               integration_id: "primary-phone",
               operation_id: "provider-leg-private"
             )

    assert {:ok, _attempt, observations} =
             TelephonyAttempt.start(
               %{
                 tenant_id: plan.tenant_id,
                 call_id: plan.call_id,
                 room_id: room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: caller.participant_id
               },
               "tleg-private-usage",
               provider,
               ~U[2026-09-12 04:30:00.000Z]
             )

    assert :ok = CallEngine.record_telephony_usage(observations)
    fact = :usage_observed |> collect_archive_facts_through() |> List.last()
    assert fact.kind == :usage_observed
    assert fact.participant_id == caller.participant_id
    assert fact.activation_id == nil
    assert fact.payload["capability"] == "telephony"
    assert fact.payload["attribution"]["leg_id"] == "tleg-private-usage"
    assert fact.payload["provider"]["operation_id"] == "provider-leg-private"
    refute_receive {:vxpipe_event, %{kind: :usage_observed}}
  end

  test "starts only entry participants and routes an attached caller through Agent Runtime" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    unused = Map.fetch!(plan.participants, "unused-agent")

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert room.room_id == room_id

    assert %Snapshot{revision: 2, present_participant_ids: present_participant_ids} =
             Authority.snapshot(Authority.whereis(room.incarnation_id))

    assert present_participant_ids ==
             MapSet.new([caller.participant_id, receiver.participant_id])

    assert %{policy_revision: 2} = RoomMixer.stats(RoomMixer.whereis(room.incarnation_id))

    assert participant_registered?(room_id, caller.participant_id)
    assert participant_registered?(room_id, receiver.participant_id)
    refute participant_registered?(room_id, unused.participant_id)
    assert AgentActivationSupervisor.whereis_child(unused.activation_id, :session) == nil

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "conn-definition-test",
               deadline: future_deadline()
             )

    assert {:ok, attachment} = CallEngine.attach_connection(attach)
    Vxpipe.CallEngine.TestCallStartup.await_ready(attachment)

    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: attach.connection_id,
               correlation_id: "turn-definition-test",
               content: "What time is it?",
               deadline: future_deadline()
             )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)

    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).content == "What time is it?"
    assert {:ok, call} = ToolCall.new(id: "tool-clock", name: "get_current_time", arguments: %{})
    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:vxpipe_event,
                    %ToolCallStarted{
                      sequence: 3,
                      participant_id: agent_participant_id,
                      tool_call_id: "tool-clock",
                      name: "get_current_time",
                      arguments: %{}
                    }}

    assert agent_participant_id == receiver.participant_id

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      sequence: 4,
                      tool_call_id: "tool-clock",
                      result: %{"timezone" => "UTC"}
                    }}

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement_request}
    assert acknowledgement_request.tools == []
    assert {:ok, response} = ModelResponse.new(text: "The host action started.")
    send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 5, text: "The host action started."}}

    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    assert {:ok, response} = ModelResponse.new(text: "The host action completed.")
    send(completion_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 7, text: "The host action completed."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 8}}
  end

  test "ends a planned room if its media policy authority exits" do
    room_id = unique_id("room-policy-authority-exit")
    plan = compile_plan(room_id)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    room_monitor = Process.monitor(room_authority)
    _ = :sys.get_state(room_authority)
    policy_authority = Authority.whereis(room.incarnation_id)

    Process.exit(policy_authority, :kill)

    assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :shutdown}, 2_000
  end

  test "ends a planned room if its registered room mixer exits" do
    room_id = unique_id("room-mixer-exit")
    plan = compile_plan(room_id)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    room_monitor = Process.monitor(room_authority)
    _ = :sys.get_state(room_authority)
    room_mixer = RoomMixer.whereis(room.incarnation_id)

    Process.exit(room_mixer, :kill)

    assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :shutdown}, 2_000
  end

  test "supervises transcript policy with the room and fails closed if it exits" do
    room_id = unique_id("room-transcript-router-exit")
    plan = compile_plan(room_id)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    room_monitor = Process.monitor(room_authority)
    _ = :sys.get_state(room_authority)
    transcript_router = TranscriptRouter.whereis(room.incarnation_id)

    assert %{policy_revision: 2} = TranscriptRouter.stats(transcript_router)
    Process.exit(transcript_router, :kill)

    assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :shutdown}, 2_000
  end

  test "discards a prepared participant that is absent from the pinned policy catalog" do
    room_id = unique_id("room-unplanned-participant")
    plan = compile_plan(room_id)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               participant_id: "unplanned-participant",
               role: :human,
               deadline: future_deadline()
             )

    assert {:error, %Error{code: :room_start_failed}} = CallEngine.join_participant(join)
    refute participant_registered?(room_id, "unplanned-participant")

    assert %Snapshot{revision: 2} =
             Authority.snapshot(Authority.whereis(room.incarnation_id))
  end

  test "starts a room-owned Call Variables process independently of RoomAuthority" do
    room_id = unique_id("room-variables")
    plan = compile_variables_plan(room_id)

    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    handoff = open_archive(maximum_pending_facts: 8)
    archive_monitor = Process.monitor(handoff.subscriber)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive_handoff: handoff)

    assert_receive {:test_archive_write, baseline_writer, %BaselineSnapshot{call_id: call_id}}
    assert call_id == plan.call_id
    send(baseline_writer, {:test_archive_write_result, :ok})

    assert variables = CallVariables.whereis(room.incarnation_id)

    assert {:ok, command} =
             ReadCallVariables.new(
               tenant_id: plan.tenant_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: receiver.participant_id,
               sections: ["order"],
               deadline: future_deadline()
             )

    assert [{authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    :ok = :sys.suspend(authority)

    try do
      assert {:ok,
              %{
                "sections" => %{
                  "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
                }
              }} = CallVariables.read(variables, command)
    after
      :ok = :sys.resume(authority)
    end

    assert {:ok, update} =
             UpdateCallVariables.new(
               tenant_id: plan.tenant_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: receiver.participant_id,
               activation_id: receiver.activation_id,
               source_participant_id: plan.participants[plan.entry_caller].participant_id,
               correlation_id: "turn-variables",
               tool_call_id: "tool-variables",
               section: "intake",
               expected_revision: 0,
               operation: {:put, "summary", "ready"},
               deadline: future_deadline()
             )

    assert {:ok, %{"revision" => 1}} = CallVariables.update(variables, update)

    assert_receive {:test_archive_write, update_writer,
                    %UpdateSnapshot{
                      room_id: ^room_id,
                      section: "intake",
                      section_revision: 1,
                      sections: %{
                        "order" => %{value: %{"id" => "order-1"}},
                        "intake" => %{value: %{"summary" => "ready"}}
                      }
                    }},
                   5_000

    assert [{activation, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, receiver.activation_id, :supervisor}
             )

    activation_monitor = Process.monitor(activation)
    :ok = Supervisor.stop(activation)
    assert_receive {:DOWN, ^activation_monitor, :process, ^activation, _reason}

    assert CallVariables.whereis(room.incarnation_id) == variables

    assert {:ok, %{"sections" => %{"order" => %{"value" => %{"id" => "order-1"}}}}} =
             CallVariables.read(variables, command)

    send(update_writer, {:test_archive_write_result, :ok})
    assert eventually(fn -> Handoff.stats(handoff).pending == 0 end)

    Process.exit(authority, :shutdown)
    assert_receive {:DOWN, ^archive_monitor, :process, _subscriber, :normal}
  end

  test "executes generated variable actions through the definition-driven Agent Runtime loop" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-variable-actions")
    plan = compile_variables_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    archive = archive_options()

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: Keyword.put(archive, :enabled, true)
             )

    assert_receive {:test_archive_write, baseline_writer, %BaselineSnapshot{}}
    send(baseline_writer, {:test_archive_write_result, :ok})

    attach_caller(plan, room, caller, "conn-variable-actions")

    command =
      send_command(
        plan,
        room,
        caller,
        "conn-variable-actions",
        "Collect the intake details."
      )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)

    assert_receive {:test_agent_runtime_stream, read_provider, read_request}

    assert Enum.map(read_request.tools, & &1.name) == [
             "get_current_time",
             "read_variables",
             "update_variable",
             "update_variables"
           ]

    assert read_request.model_context == %{
             "call_variables" => %{
               "global_revision" => 0,
               "sections" => %{
                 "intake" => %{"revision" => 0, "value" => nil},
                 "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
               }
             }
           }

    assert {:ok, read_call} =
             ToolCall.new(
               id: "tool-read-variables",
               name: "read_variables",
               arguments: %{"sections" => ["order"]}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [read_call])
    send(read_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "tool-read-variables",
                      result: %{
                        "global_revision" => 0,
                        "sections" => %{
                          "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
                        }
                      }
                    }},
                   2_000

    assert_receive {:test_agent_runtime_stream, read_ack_provider, read_ack_request}
    assert read_ack_request.tools == []
    assert {:ok, response} = ModelResponse.new(text: "I am reading the order details.")
    send(read_ack_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_stream, update_provider, update_request}
    assert List.last(update_request.messages).origin == :engine

    assert {:ok, update_call} =
             ToolCall.new(
               id: "tool-update-variables",
               name: "update_variables",
               arguments: %{
                 "section_name" => "intake",
                 "data" => %{"summary" => "Asked for assistance"},
                 "expected_revision" => 0
               }
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [update_call])
    send(update_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "tool-update-variables",
                      result: %{
                        "section" => "intake",
                        "revision" => 1,
                        "value" => %{"summary" => "Asked for assistance"}
                      }
                    }},
                   2_000

    assert_receive {:test_agent_runtime_stream, update_ack_provider, update_ack_request}
    assert update_ack_request.tools == []
    assert {:ok, response} = ModelResponse.new(text: "I am saving the intake details.")
    send(update_ack_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_archive_write, update_writer,
                    %UpdateSnapshot{
                      participant_id: participant_id,
                      tool_call_id: "tool-update-variables",
                      section: "intake",
                      section_revision: 1
                    }},
                   2_000

    assert participant_id == receiver.participant_id
    send(update_writer, {:test_archive_write_result, :ok})

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine

    assert completion_request.model_context == %{
             "call_variables" => %{
               "global_revision" => 1,
               "sections" => %{
                 "intake" => %{
                   "revision" => 1,
                   "value" => %{"summary" => "Asked for assistance"}
                 },
                 "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
               }
             }
           }

    assert {:ok, response} = ModelResponse.new(text: "The intake details are saved.")
    send(completion_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %TextOutput{text: "The intake details are saved."}},
                   2_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 2_000
  end

  test "routes the next room turn through a restarted agent activation" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert [{activation_supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, receiver.activation_id, :supervisor}
             )

    first = AgentActivationSupervisor.children(activation_supervisor)
    monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :session), :kill)
    assert_children_stopped(monitors)
    _ = :sys.get_state(activation_supervisor)

    second = AgentActivationSupervisor.children(activation_supervisor)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    attach_caller(plan, room, caller, "conn-restarted")
    command = send_command(plan, room, caller, "conn-restarted", "Are you ready?")

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)
    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).content == "Are you ready?"
    assert {:ok, response} = ModelResponse.new(text: "Ready after restart.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "Ready after restart."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 4}}
  end

  test "pins inline speech options while using tenant credentials and configured transports" do
    configure_agent_runtime_provider(self())
    configure_speech_runtime()
    room_id = unique_id("room")
    plan = compile_plan(room_id, speech?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert_receive {:test_tts_transport_started, _tts_transport,
                    %{url: tts_url, headers: [{"Authorization", "Token runtime-test-secret"}]}}

    assert tts_url =~ "model=flux-plan-voice"

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    attach_caller(plan, room, caller, "conn-speech-plan", sink)

    assert_receive {:test_stt_transport_started, _stt_transport,
                    %{url: stt_url, headers: [{"Authorization", "Token runtime-test-secret"}]}}

    assert stt_url =~ "model=flux-general-multi"
  end

  for provider <- [:deepgram, :morse] do
    test "resolves #{provider} only when an additional planned human attaches" do
      configure_agent_runtime_provider(self())
      configure_speech_runtime()

      plan =
        compile_plan(unique_id("room-late-human"),
          speech?: true,
          definition_transform: fn input ->
            listener = %{
              Map.fetch!(input.participants, "caller")
              | capabilities: %{
                  speech_to_text: speech_selection(:speech_to_text, unquote(provider))
                }
            }

            put_in(input, [:participants, "listener"], listener)
          end
        )

      caller = Map.fetch!(plan.participants, plan.entry_caller)
      listener = Map.fetch!(plan.participants, "listener")
      assert {:ok, room} = CallEngine.TestCallStartup.start_call(plan)
      assert_receive {:test_tts_transport_started, _voice, _}
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      attach_caller(plan, room, caller, "original-caller", sink)
      assert_receive {:test_stt_transport_started, caller_stt, _}
      refute_receive {:test_stt_transport_started, _, _}

      [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
      assert {:ok, before} = RoomAuthority.readiness_binding(authority)

      assert {:ok, join} =
               JoinParticipant.new(
                 tenant_id: plan.tenant_id,
                 actor_id: plan.actor_id,
                 room_id: plan.room_id,
                 participant_id: listener.participant_id,
                 role: :human,
                 deadline: future_deadline()
               )

      assert {:ok, _participant} = CallEngine.join_participant(join)
      refute_receive {:test_stt_transport_started, _, _}

      assert {:ok, attach} =
               AttachConnection.new(
                 tenant_id: plan.tenant_id,
                 actor_id: plan.actor_id,
                 room_id: plan.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: listener.participant_id,
                 connection_id: "late-listener",
                 deadline: future_deadline()
               )

      result = CallEngine.TestTransferConnection.attach(attach, nil)

      if unquote(provider) == :deepgram do
        assert {:ok, %ConnectionAttachment{media_ingress: ingress}} = result
        assert is_pid(ingress)
        assert_receive {:test_stt_transport_started, listener_stt, %{url: url}}
        assert listener_stt != caller_stt
        assert url =~ "model=flux-general-multi"
      else
        assert {:error, %Error{code: :speech_to_text_unavailable}} = result
      end

      assert {:ok, after_attachment} = RoomAuthority.readiness_binding(authority)
      assert after_attachment.room == before.room
      assert after_attachment.participants == before.participants

      assert Map.fetch!(after_attachment.connections, "original-caller") ==
               Map.fetch!(before.connections, "original-caller")

      refute_receive {:test_stt_transport_started, _, _}
      refute_receive {:test_tts_transport_started, _, _}
    end
  end

  test "resolves explicitly registered alternate speech providers without changing defaults" do
    plan = compile_plan(unique_id("room-morse-runtime"), speech?: true, speech_provider: :morse)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    default_stt = [
      enabled: true,
      provider: Flux,
      provider_options: [api_key: "unused-default"],
      transport: {TestSpeechToTextTransport, []},
      media_ingress: media_ingress_options()
    ]

    default_tts = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [api_key: "unused-default"],
      transport: {TestTextToSpeechTransport, []},
      maximum_requests: 2
    ]

    speech_to_text =
      Keyword.put(default_stt, :providers, %{
        MorseCodeSTT => [
          enabled: true,
          provider_options: [],
          transport: {MorseCodeSTT.Transport, []},
          media_ingress: media_ingress_options()
        ]
      })

    text_to_speech =
      Keyword.put(default_tts, :providers, %{
        MorseCodeTTS => [
          enabled: true,
          provider_options: [],
          transport: {MorseCodeTTS.Transport, []},
          maximum_requests: 2
        ]
      })

    assert {:ok, startup} =
             PlanStartup.new(plan,
               owner: self(),
               agent_runtime: Keyword.fetch!(settings, :agent_runtime),
               agent_request_options: [],
               speech_to_text: speech_to_text,
               text_to_speech: text_to_speech
             )

    speech_to_text =
      Map.fetch!(startup.speech_to_text_runtimes, caller.participant_id)

    assert {MorseCodeSTT, %MorseConfig{sample_rate: 16_000, unit_duration_ms: 20}} =
             speech_to_text.provider

    assert speech_to_text.transport == {MorseCodeSTT.Transport, []}
    assert speech_to_text.call_id == plan.call_id
    assert speech_to_text.participant_id == caller.participant_id
    assert speech_to_text.activation_id == caller.activation_id
    assert speech_to_text.usage_provider.name == "morse_code"

    assert speech_to_text.usage_provider.integration_id ==
             Vxpipe.CallEngine.CallDefinition.CapabilitySelection.identity(
               caller.capabilities.speech_to_text,
               plan.tenant_id
             )

    assert {MorseCodeTTS, %MorseConfig{sample_rate: 16_000, unit_duration_ms: 20}} =
             startup.text_to_speech.provider

    assert startup.text_to_speech.transport == {MorseCodeTTS.Transport, []}
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    assert startup.text_to_speech.call_id == plan.call_id
    assert startup.text_to_speech.participant_id == receiver.participant_id
    assert startup.text_to_speech.activation_id == receiver.activation_id
    assert startup.text_to_speech.usage_provider.name == "morse_code"

    assert startup.text_to_speech.usage_provider.integration_id ==
             Vxpipe.CallEngine.CallDefinition.CapabilitySelection.identity(
               receiver.capabilities.text_to_speech,
               plan.tenant_id
             )

    assert Keyword.fetch!(default_stt, :provider) == Flux
    assert Keyword.fetch!(default_tts, :provider) == FluxTextToSpeech
  end

  test "keeps the active agent pinned after source prompt and inline selection change" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-pinned-source")
    input = definition_input([])
    plan = compile_plan_from(room_id, input)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    changed_input =
      put_in(input, [:participants, "receiver", :prompt], "Use a replacement prompt.")

    changed_input =
      put_in(
        changed_input,
        [:participants, "receiver", :capabilities, :model_inference, :model],
        "replacement:model"
      )

    assert get_in(changed_input, [:participants, "receiver", :prompt]) ==
             "Use a replacement prompt."

    assert changed_input.participants["receiver"].capabilities.model_inference.model ==
             "replacement:model"

    assert room.room_id == room_id

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    attach_caller(plan, room, caller, "conn-pinned-source")
    command = send_command(plan, room, caller, "conn-pinned-source", "Check the pinned agent.")
    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)

    assert_receive {:test_agent_runtime_stream, provider, request}

    assert [%Message{role: :system, content: "Use the available host action."} | _messages] =
             request.messages

    assert receiver.capabilities.model_inference.model == "test:scripted"

    assert {:ok, response} = ModelResponse.new(text: "Pinned configuration retained.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  test "projects an application-configured local model fixture into agent startup" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Local fixture response."}
      )

    plan = compile_plan(unique_id("room-fixture"))
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      settings
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {AgentRuntimeModelProvider, [fixture: fixture]})

    assert {:ok, startup} =
             PlanStartup.new(plan,
               owner: self(),
               agent_runtime: agent_runtime,
               agent_request_options: [],
               speech_to_text: [enabled: false],
               text_to_speech: [enabled: false]
             )

    assert startup.agent_activation[:provider] == "fixture"
    assert startup.agent_activation[:runtime] == :agent_runtime
    assert startup.agent_activation[:model_provider] == AgentRuntimeModelProvider
    assert startup.agent_activation[:model].fixture == fixture
    assert startup.agent_activation[:model].model == "test:scripted"
  end

  test "rejects the retired Jido implementation during plan startup" do
    plan = compile_plan(unique_id("room-retired-jido"))
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      settings
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :jido)

    assert {:error, %Error{code: :unsupported_call_plan}} =
             PlanStartup.new(plan,
               owner: self(),
               agent_runtime: agent_runtime,
               agent_request_options: [],
               speech_to_text: [enabled: false],
               text_to_speech: [enabled: false]
             )
  end

  test "starts an explicitly selected Agent Runtime activation through room authority" do
    configure_agent_runtime_provider(self())
    room_id = unique_id("room-agent-runtime")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    assert is_pid(AgentActivationSupervisor.whereis_child(receiver.activation_id, :session))

    attach_caller(plan, room, caller, "conn-agent-runtime")
    command = send_command(plan, room, caller, "conn-agent-runtime", "Hello Agent Runtime")

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: correlation_id}}
    assert correlation_id == command.correlation_id
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{correlation_id: ^correlation_id}}

    assert_receive {:test_agent_runtime_stream, provider, request}

    assert [%Message{role: :system, content: "Use the available host action."} | _history] =
             request.messages

    assert Enum.map(request.tools, & &1.name) == ["get_current_time"]

    assert {:ok, response} = ModelResponse.new(text: "Hello through Agent Runtime.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %TextOutput{text: "Hello through Agent Runtime."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^correlation_id}}
  end

  test "runs controlled local model outcomes through the complete room turn" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Local fixture response."}
      )

    configure_model_fixture(fixture)
    room_id = unique_id("room-fixture-turn")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    attach_caller(plan, room, caller, "conn-fixture-turn")

    success = send_command(plan, room, caller, "conn-fixture-turn", "use local success")
    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(success)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: success_correlation}}
    assert success_correlation == success.correlation_id

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{correlation_id: ^success_correlation}}

    assert_receive {:vxpipe_event, %TextOutput{text: "Local fixture response."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^success_correlation}}

    assert :ok = ModelFixture.arm(fixture, :failure)
    failed = send_command(plan, room, caller, "conn-fixture-turn", "use local failure")
    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(failed)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: failure_correlation}}
    assert failure_correlation == failed.correlation_id

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{correlation_id: ^failure_correlation}}

    assert_receive {:vxpipe_event,
                    %AgentTurnFailed{
                      correlation_id: ^failure_correlation,
                      reason: :provider_unavailable
                    }}

    assert :ok = ModelFixture.arm(fixture, :missing)
    missing = send_command(plan, room, caller, "conn-fixture-turn", "omit local output")
    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(missing)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: missing_correlation}}
    assert missing_correlation == missing.correlation_id

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{correlation_id: ^missing_correlation}}

    assert_receive {:vxpipe_event,
                    %AgentTurnFailed{
                      correlation_id: ^missing_correlation,
                      reason: :invalid_response
                    }}

    refute_receive {:vxpipe_event, %TextOutput{correlation_id: ^missing_correlation}}
  end

  test "cleans the attempted room tree when the selected provider transport fails to start" do
    observer = self()

    before_failure = fn ->
      send(observer, {:failure_waiting, self()})

      receive do
        :fail_startup -> :ok
      end
    end

    configure_speech_runtime(
      text_to_speech_transport:
        {TestFailingTextToSpeechTransport, [observer: self(), before_failure: before_failure]}
    )

    room_id = unique_id("room-provider-start-failure")
    plan = compile_plan(room_id, speech?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, _room} = CallEngine.start_call(plan)
    assert_receive {:failure_waiting, worker}, 1_000
    [{authority, _}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})
    monitor = Process.monitor(authority)
    send(worker, :fail_startup)
    assert_receive {:DOWN, ^monitor, :process, ^authority, :startup_unavailable}, 1_000
    assert_receive {:test_failing_tts_start_attempted, %{url: attempted_url}}
    assert attempted_url =~ "model=flux-plan-voice"
    refute_receive {:test_failing_tts_start_attempted, _second_attempt}
    refute_receive {:test_tts_transport_started, _transport, _connection}

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {plan.tenant_id, room_id}
           ) == []

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {:participant, plan.tenant_id, room_id, caller.participant_id}
           ) == []

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {:participant, plan.tenant_id, room_id, receiver.participant_id}
           ) == []

    assert AgentActivationSupervisor.whereis_child(receiver.activation_id, :session) == nil
  end

  test "rejects an unsupported model provider before registering a room" do
    room_id = unique_id("room-unsupported-provider")
    plan = compile_plan(room_id)
    receiver = plan.participants["receiver"]
    invalid = %{receiver.capabilities.model_inference | provider: "unsupported"}
    receiver = %{receiver | capabilities: %{receiver.capabilities | model_inference: invalid}}
    plan = %{plan | participants: Map.put(plan.participants, "receiver", receiver)}

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{
                "path" => [
                  "participants",
                  "receiver",
                  "capabilities",
                  "model_inference"
                ]
              }
            }} = CallEngine.start_call(plan)

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {plan.tenant_id, room_id}
           ) == []
  end

  test "rejects selected speech that the application runtime cannot provide" do
    room_id = unique_id("room-unsupported-speech")
    plan = compile_plan(room_id, speech?: true)

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{
                "path" => [
                  "participants",
                  "caller",
                  "capabilities",
                  "speech_to_text"
                ]
              }
            }} = CallEngine.start_call(plan)

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {plan.tenant_id, room_id}
           ) == []
  end

  defp compile_plan(room_id, options \\ []) do
    transform = Keyword.get(options, :definition_transform, &Function.identity/1)
    input = options |> definition_input() |> transform.()
    compile_plan_from(room_id, input, options)
  end

  defp open_archive(options) do
    options = archive_options(options)

    assert {:ok, handoff} = ArchiveSupervisor.open(options)

    on_exit(fn ->
      if Process.alive?(handoff.subscriber) do
        Handoff.source_stopped(handoff, :test_cleanup)
      end
    end)

    handoff
  end

  defp archive_options(options \\ []) do
    Keyword.merge(
      [
        writer: {TestArchiveWriter, self()},
        maximum_pending_facts: 4,
        retry_delay_ms: 5,
        drain_timeout_ms: 1_000
      ],
      options
    )
  end

  defp collect_archive_facts_through(kind, count \\ 1, facts \\ [])

  defp collect_archive_facts_through(kind, count, facts) when count > 0 do
    receive do
      {:test_archive_fact, %Fact{kind: ^kind} = fact} ->
        if count == 1 do
          Enum.reverse([fact | facts])
        else
          collect_archive_facts_through(kind, count - 1, [fact | facts])
        end

      {:test_archive_fact, %Fact{} = fact} ->
        collect_archive_facts_through(kind, count, [fact | facts])

      {:test_archive_fact, _other_archive_value} ->
        collect_archive_facts_through(kind, count, facts)
    after
      2_000 -> flunk("timed out waiting for archived #{kind}")
    end
  end

  defp fact!(facts, kind) do
    Enum.find(facts, &(&1.kind == kind)) || flunk("missing archived #{kind}")
  end

  defp compile_variables_plan(room_id) do
    transform = fn input ->
      input
      |> put_in([:call_variables, :sections], %{
        "order" => %{
          schema: %{
            "type" => "object",
            "properties" => %{"id" => %{"type" => "string"}},
            "additionalProperties" => false
          }
        },
        "intake" => %{
          schema: %{
            "type" => "object",
            "properties" => %{"summary" => %{"type" => "string"}},
            "additionalProperties" => false
          }
        }
      })
      |> put_in(
        [:participants, "receiver", :variable_permissions],
        %{"order" => ["read"], "intake" => ["read", "write"]}
      )
    end

    compile_plan(room_id,
      definition_transform: transform,
      initial_variables: %{"order" => %{"id" => "order-1"}}
    )
  end

  defp compile_plan_from(room_id, input, options \\ []) do
    assert {:ok, definition} =
             CallDefinition.new(input,
               resource_id: "definition-test",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "definition-test", revision: 1},
                 initial_variables: Keyword.get(options, :initial_variables, %{}),
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               call_id: unique_id("call"),
               room_id: room_id
             )

    registries = %{
      host_tools: %{"get_current_time" => CurrentTime}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp speech_selection(_kind, :morse) do
    %{provider: "morse", model: "morse", options: %{sample_rate: 16_000, unit_duration_ms: 20}}
  end

  defp speech_selection(:speech_to_text, :deepgram) do
    %{
      provider: "deepgram",
      model: "flux-general-multi",
      options: %{encoding: "opus", sample_rate: 48_000}
    }
  end

  defp speech_selection(:text_to_speech, :deepgram) do
    %{
      provider: "deepgram",
      model: "flux-plan-voice",
      options: %{encoding: "linear16", sample_rate: 48_000}
    }
  end

  defp definition_input(options) do
    speech? = Keyword.get(options, :speech?, false)

    speech_provider = Keyword.get(options, :speech_provider, :deepgram)

    caller_capabilities =
      if speech?,
        do: %{speech_to_text: speech_selection(:speech_to_text, speech_provider)},
        else: %{}

    receiver_capabilities =
      if speech?,
        do: %{text_to_speech: speech_selection(:text_to_speech, speech_provider)},
        else: %{}

    %{
      schema_version: CallDefinition.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: caller_capabilities
        },
        "receiver" => %{
          type: "agent",
          prompt: "Use the available host action.",
          first_message: %{mode: "wait_for_input"},
          capabilities:
            Map.put(receiver_capabilities, :model_inference, %{
              provider: "fixture",
              model: "test:scripted"
            }),
          tools: %{
            "get_current_time" => %{type: "host", tool: "get_current_time"}
          },
          transfers: []
        },
        "unused-agent" => %{
          type: "agent",
          prompt: "This participant must not be started.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp participant_registered?(room_id, participant_id) do
    case Registry.lookup(
           Vxpipe.CallEngine.RoomRegistry,
           {:participant, "tenant-test", room_id, participant_id}
         ) do
      [{pid, _value}] -> Process.alive?(pid)
      [] -> false
    end
  end

  defp attach_caller(plan, room, caller, connection_id, output_sink \\ nil) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    assert {:ok, attachment} =
             Vxpipe.CallEngine.TestTransferConnection.attach(command, output_sink)

    Vxpipe.CallEngine.TestCallStartup.await_ready(plan.room_id)
    {:ok, attachment}
  end

  defp send_command(plan, room, caller, connection_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    command
  end

  defp stt_turn_message(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-private-history",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if trigger == nil, do: message, else: Map.put(message, "trigger", trigger)
    JSON.encode!(message)
  end

  defp monitor_children(children) do
    Map.new(children, fn {role, pid} -> {role, {pid, Process.monitor(pid)}} end)
  end

  defp assert_children_stopped(monitors) do
    Enum.each(monitors, fn {_role, {pid, monitor}} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end)
  end

  defp configure_speech_runtime(options \\ []) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-general-en",
        encoding: :opus,
        sample_rate: 48_000
      ],
      transport: {TestSpeechToTextTransport, [observer: self(), ready_on_start: true]},
      media_ingress: media_ingress_options()
    ]

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport:
        Keyword.get(
          options,
          :text_to_speech_transport,
          {TestTextToSpeechTransport, [observer: self(), ready_on_start: true]}
        ),
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp configure_model_fixture(fixture) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {AgentRuntimeModelProvider, [fixture: fixture]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp configure_agent_runtime_provider(observer) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestAgentRuntimeModelProvider, [owner: observer]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp media_ingress_options do
    [
      maximum_frames: 50,
      maximum_bytes: 262_144,
      maximum_age_ms: 2_000,
      maximum_consecutive_overflows: 5
    ]
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp eventually(predicate, attempts \\ 100)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(5)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
