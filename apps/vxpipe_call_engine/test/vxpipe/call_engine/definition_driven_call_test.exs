defmodule Vxpipe.CallEngine.DefinitionDrivenCallTest do
  use ExUnit.Case, async: false

  import Jido.AI.Test

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
    PlanStartup
  }

  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
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

  alias Vxpipe.CallEngine.{
    TestAudioOutputSink,
    TestArchiveWriter,
    TestCollectingArchiveWriter,
    TestFailingTextToSpeechTransport,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport
  }

  test "archives private lifecycle, accepted input, tool, and generated-output facts" do
    room_id = unique_id("room-private-history")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    script =
      expect_react do
        user("What time is it?")
        call("get_current_time", %{}, id: "tool-private-history")
        answer("The host action completed.")
      end

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 64
      )

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script),
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

    assert :ok = CallEngine.send_text(command)

    facts = collect_archive_facts_through(:agent_turn_completed)

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

    assert %Fact{
             kind: :agent_output_generated,
             public_sequence: 5,
             payload: %{
               "aggregated_by" => "sentence",
               "text" => "The host action completed.",
               "will_be_spoken" => false
             }
           } = fact!(facts, :agent_output_generated)

    assert %Fact{kind: :agent_turn_completed, public_sequence: 6} =
             fact!(facts, :agent_turn_completed)
  end

  test "archives final audio input and distinguishes generated from delivered output" do
    configure_speech_runtime()
    room_id = unique_id("room-private-audio-history")
    plan = compile_plan(room_id, speech?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    script =
      expect_react do
        user("Hello there")
        answer("Hello back.")
      end

    archive =
      archive_options(
        writer: {TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 64
      )

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script),
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
  end

  test "starts only entry participants and routes an attached caller through Jido" do
    room_id = unique_id("room")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    unused = Map.fetch!(plan.participants, "unused-agent")

    script =
      expect_react do
        user("What time is it?")
        call("get_current_time", %{}, id: "tool-clock")
        answer("The host action completed.")
      end

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script)
             )

    assert room.room_id == room_id

    assert participant_registered?(room_id, caller.participant_id)
    assert participant_registered?(room_id, receiver.participant_id)
    refute participant_registered?(room_id, unused.participant_id)
    assert AgentActivationSupervisor.whereis_child(unused.activation_id, :agent_server) == nil

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

    assert {:ok, _attachment} = CallEngine.attach_connection(attach)

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

    assert :ok = CallEngine.send_text(command)

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

    assert_receive {:vxpipe_event, %TextOutput{sequence: 5, text: "The host action completed."}}

    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}
  end

  test "starts a room-owned Call Variables process independently of RoomAuthority" do
    room_id = unique_id("room-variables")
    plan = compile_variables_plan(room_id)

    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    handoff = open_archive()
    archive_monitor = Process.monitor(handoff.subscriber)

    assert {:ok, room} = CallEngine.start_call(plan, archive_handoff: handoff)

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
                    }}

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

  test "executes generated variable actions through the definition-driven Jido loop" do
    room_id = unique_id("room-variable-actions")
    plan = compile_variables_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    archive = archive_options()

    script =
      expect_react do
        user("Collect the intake details.")
        call("read_variables", %{"sections" => ["order"]}, id: "tool-read-variables")

        call(
          "update_variables",
          %{
            "section_name" => "intake",
            "data" => %{"summary" => "Asked for assistance"},
            "expected_revision" => 0
          },
          id: "tool-update-variables"
        )

        answer("The intake details are saved.")
      end

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script),
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

    assert :ok = CallEngine.send_text(command)

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

    assert_receive {:vxpipe_event, %TextOutput{text: "The intake details are saved."}},
                   2_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 2_000
  end

  test "routes the next room turn through a restarted agent activation" do
    room_id = unique_id("room")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    script =
      expect_react do
        user("Are you ready?")
        answer("Ready after restart.")
      end

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script)
             )

    assert [{activation_supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, receiver.activation_id, :supervisor}
             )

    first = AgentActivationSupervisor.children(activation_supervisor)
    monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :agent_server), :kill)
    assert_children_stopped(monitors)
    _ = :sys.get_state(activation_supervisor)

    second = AgentActivationSupervisor.children(activation_supervisor)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    attach_caller(plan, room, caller, "conn-restarted")
    command = send_command(plan, room, caller, "conn-restarted", "Are you ready?")

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "Ready after restart."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 4}}
  end

  test "pins selected speech options while using application-owned secrets and transports" do
    configure_speech_runtime()
    room_id = unique_id("room")
    plan = compile_plan(room_id, speech?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    script =
      expect_react do
        user("Hello")
        answer("Hello back.")
      end

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script)
             )

    assert_receive {:test_tts_transport_started, _tts_transport,
                    %{url: tts_url, headers: [{"Authorization", "Token runtime-secret"}]}}

    assert tts_url =~ "model=flux-plan-voice"

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    attach_caller(plan, room, caller, "conn-speech-plan", sink)

    assert_receive {:test_stt_transport_started, _stt_transport,
                    %{url: stt_url, headers: [{"Authorization", "Token runtime-secret"}]}}

    assert stt_url =~ "model=flux-general-multi"
  end

  test "resolves explicitly registered alternate speech providers without changing defaults" do
    plan = compile_plan(unique_id("room-morse-runtime"), speech?: true, speech_profile: :morse)
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

    assert {MorseCodeSTT, %MorseConfig{sample_rate: 16_000, unit_duration_ms: 20}} =
             startup.speech_to_text.provider

    assert startup.speech_to_text.transport == {MorseCodeSTT.Transport, []}

    assert {MorseCodeTTS, %MorseConfig{sample_rate: 16_000, unit_duration_ms: 20}} =
             startup.text_to_speech.provider

    assert startup.text_to_speech.transport == {MorseCodeTTS.Transport, []}
    assert Keyword.fetch!(default_stt, :provider) == Flux
    assert Keyword.fetch!(default_tts, :provider) == FluxTextToSpeech
  end

  test "keeps the active agent pinned after source definition and profile maps change" do
    room_id = unique_id("room-pinned-source")
    input = definition_input([])
    profiles = capability_profiles([])
    plan = compile_plan_from(room_id, input, profiles)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, room} = CallEngine.start_call(plan)

    changed_input =
      put_in(input, [:participants, "receiver", :prompt], "Use a replacement prompt.")

    changed_profiles =
      put_in(profiles, ["test-model", :options, :model], "replacement:model")

    assert get_in(changed_input, [:participants, "receiver", :prompt]) ==
             "Use a replacement prompt."

    assert get_in(changed_profiles, ["test-model", :options, :model]) == "replacement:model"
    assert room.room_id == room_id

    agent_server =
      AgentActivationSupervisor.whereis_child(receiver.activation_id, :agent_server)

    assert {:ok, agent_state} = Jido.AgentServer.state(agent_server)
    agent_config = Jido.AI.get_strategy_config(agent_state.agent)

    assert agent_config.system_prompt == "Use the available host action."
    assert receiver.capabilities.model_inference.options == %{model: "test:scripted"}
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
      |> Keyword.put(:model_fixture, fixture)

    assert {:ok, startup} =
             PlanStartup.new(plan,
               owner: self(),
               agent_runtime: agent_runtime,
               agent_request_options: [],
               speech_to_text: [enabled: false],
               text_to_speech: [enabled: false]
             )

    assert startup.agent_activation[:provider] == :local_fixture

    assert startup.agent_activation[:request_options][:tool_context][:vxpipe_model_fixture] ==
             fixture
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

    assert {:ok, room} = CallEngine.start_call(plan)
    attach_caller(plan, room, caller, "conn-fixture-turn")

    success = send_command(plan, room, caller, "conn-fixture-turn", "use local success")
    assert :ok = CallEngine.send_text(success)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: success_correlation}}
    assert success_correlation == success.correlation_id

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{correlation_id: ^success_correlation}}

    assert_receive {:vxpipe_event, %TextOutput{text: "Local fixture response."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^success_correlation}}

    assert :ok = ModelFixture.arm(fixture, :failure)
    failed = send_command(plan, room, caller, "conn-fixture-turn", "use local failure")
    assert :ok = CallEngine.send_text(failed)
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
    assert :ok = CallEngine.send_text(missing)
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
    configure_speech_runtime(
      text_to_speech_transport: {TestFailingTextToSpeechTransport, [observer: self()]}
    )

    room_id = unique_id("room-provider-start-failure")
    plan = compile_plan(room_id, speech?: true)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:error, %Error{code: :room_start_failed}} = CallEngine.start_call(plan)
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

    assert AgentActivationSupervisor.whereis_child(receiver.activation_id, :agent_server) == nil
  end

  test "rejects enabled later-slice features before registering a room" do
    cases = [
      {fn input ->
         put_in(
           input,
           [:participants, "receiver", :first_message],
           %{mode: "generated"}
         )
       end, ["participants", "receiver", "first_message", "mode"]}
    ]

    for {transform, expected_path} <- cases do
      room_id = unique_id("room-unsupported")
      plan = compile_plan(room_id, definition_transform: transform)

      assert {:error,
              %Error{
                code: :unsupported_call_plan,
                details: %{"path" => ^expected_path}
              }} = CallEngine.start_call(plan)

      assert Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {plan.tenant_id, room_id}
             ) == []
    end
  end

  test "rejects an unsupported model provider before registering a room" do
    room_id = unique_id("room-unsupported-provider")
    plan = compile_plan(room_id, model_provider: :unsupported_model_provider)

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
    profiles = capability_profiles(options)

    compile_plan_from(room_id, input, profiles, options)
  end

  defp open_archive(options \\ []) do
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

  defp collect_archive_facts_through(kind, facts \\ []) do
    receive do
      {:test_archive_fact, %Fact{kind: ^kind} = fact} ->
        Enum.reverse([fact | facts])

      {:test_archive_fact, %Fact{} = fact} ->
        collect_archive_facts_through(kind, [fact | facts])

      {:test_archive_fact, _other_archive_value} ->
        collect_archive_facts_through(kind, facts)
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

  defp compile_plan_from(room_id, input, profiles, options \\ []) do
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
      capability_profiles: profiles,
      host_tools: %{"get_current_time" => CurrentTime}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp capability_profiles(options) do
    %{
      "test-model" => %{
        kind: :model_inference,
        provider: Keyword.get(options, :model_provider, :req_llm),
        options: %{model: "test:scripted"}
      },
      "plan-stt" => %{
        kind: :speech_to_text,
        provider: Flux,
        options: %{model: "flux-general-multi", encoding: :opus, sample_rate: 48_000}
      },
      "plan-tts" => %{
        kind: :text_to_speech,
        provider: FluxTextToSpeech,
        options: %{model: "flux-plan-voice", encoding: :linear16, sample_rate: 48_000}
      },
      "morse-stt" => %{
        kind: :speech_to_text,
        provider: MorseCodeSTT,
        options: %{sample_rate: 16_000, unit_duration_ms: 20}
      },
      "morse-tts" => %{
        kind: :text_to_speech,
        provider: MorseCodeTTS,
        options: %{sample_rate: 16_000, unit_duration_ms: 20}
      }
    }
  end

  defp definition_input(options) do
    speech? = Keyword.get(options, :speech?, false)

    speech_profile = Keyword.get(options, :speech_profile, :hosted)

    {speech_to_text_profile, text_to_speech_profile} =
      case speech_profile do
        :hosted -> {"plan-stt", "plan-tts"}
        :morse -> {"morse-stt", "morse-tts"}
      end

    caller_capabilities =
      if speech?, do: %{speech_to_text: speech_to_text_profile}, else: %{}

    receiver_capabilities =
      if speech?, do: %{text_to_speech: text_to_speech_profile}, else: %{}

    %{
      schema_version: "20260909.01",
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
          capabilities: Map.put(receiver_capabilities, :model_inference, "test-model"),
          tools: %{
            "get_current_time" => %{type: "host", tool: "get_current_time"}
          },
          transfers: []
        },
        "unused-agent" => %{
          type: "agent",
          prompt: "This participant must not be started.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp participant_registered?(room_id, participant_id) do
    match?(
      [{_pid, _value}],
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {:participant, "tenant-test", room_id, participant_id}
      )
    )
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

    assert {:ok, _attachment} = CallEngine.attach_connection(command, output_sink)
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
      transport: {TestSpeechToTextTransport, [observer: self()]},
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
          {TestTextToSpeechTransport, [observer: self()]}
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
      |> Keyword.put(:model_fixture, fixture)

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
