defmodule Vxpipe.CallEngine.AgentTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Archive.Fact

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallSpec,
    CallInvocation,
    CallVariables,
    CallSpecCompiler,
    RoomAuthority,
    RoomParticipantSupervisor,
    TestCollectingArchiveWriter,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    TextOutput,
    ToolCallCompleted,
    ToolCallFailed
  }

  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request
  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "an allowlisted tool call commits control to the destination agent" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

    variables = CallVariables.whereis(room.incarnation_id)

    assert [{source_activation, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, reception.activation_id, :supervisor}
             )

    source_capability =
      AgentActivationSupervisor.whereis_child(reception.activation_id, :coordinator)

    assert is_pid(source_capability)
    source_monitor = Process.monitor(source_activation)
    attach_caller(plan, room, caller)

    transfer_command = send_command(plan, room, caller, "Please transfer me.")
    assert :ok = CallEngine.send_text(transfer_command)

    assert_receive {:test_agent_runtime_stream, source_provider, source_request}

    assert [%Message{role: :system, content: "Route callers safely."} | _history] =
             source_request.messages

    assert Enum.map(source_request.tools, & &1.name) == ["transfer"]

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "transfer-to-billing",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:DOWN, ^source_monitor, :process, ^source_activation, _reason}, 2_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "transfer-to-billing",
                      name: "transfer",
                      result: %{
                        "destination" => "billing",
                        "status" => "completed"
                      }
                    }},
                   2_000

    assert_archived_transfer(
      :participant_transfer_started,
      reception,
      caller,
      billing,
      "transfer-to-billing",
      %{}
    )

    assert_archived_transfer(
      :participant_transfer_completed,
      reception,
      caller,
      billing,
      "transfer-to-billing",
      %{"outcome" => "completed"}
    )

    assert is_pid(AgentActivationSupervisor.whereis_child(billing.activation_id, :session))
    assert CallVariables.whereis(room.incarnation_id) == variables

    snapshot = RoomAuthority.snapshot(plan.tenant_id, plan.room_id)
    assert snapshot.tenant_id == room.tenant_id
    assert snapshot.room_id == room.room_id
    assert snapshot.incarnation_id == room.incarnation_id

    authority = room_authority(plan)
    state = :sys.get_state(authority)
    assert state.participant_transfer_runtime.plan.entry_caller == plan.entry_caller
    assert state.participant_transfer_runtime.plan.entry_receiver == plan.entry_receiver

    send(
      authority,
      {:vxpipe_capability_text, source_capability, transfer_command,
       "This stale source output must be ignored."}
    )

    refute_receive {:vxpipe_event,
                    %TextOutput{text: "This stale source output must be ignored."}},
                   100

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               reception.participant_id
             )

    assert {:ok, destination_snapshot} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)

    assert destination_snapshot.participant_id == billing.participant_id

    assert :ok =
             CallEngine.send_text(send_command(plan, room, caller, "Can you help with billing?"))

    {destination_provider, _destination_request} =
      receive_request_for_prompt("Handle billing requests.")

    assert {:ok, destination_response} = ModelResponse.new(text: "I can help with billing.")
    send(destination_provider, {:test_agent_runtime_response, {:ok, destination_response}})
  end

  test "all_spoken seeds confirmed caller input but excludes generated unplayed output" do
    plan = compile_plan(transfer_history: %{mode: "all_spoken"})
    caller = Map.fetch!(plan.participants, "caller")

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    attach_caller(plan, room, caller)

    remembered = send_command(plan, room, caller, "Remember invoice 17.")
    assert :ok = CallEngine.send_text(remembered)
    reply_to_next_request("This generated answer was not played.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: remembered_correlation}},
                   2_000

    assert remembered_correlation == remembered.correlation_id

    transfer = send_command(plan, room, caller, "Please transfer me to billing.")
    assert :ok = CallEngine.send_text(transfer)

    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "all-spoken-transfer",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "all-spoken-transfer"}},
                   2_000

    current = send_command(plan, room, caller, "Can you see what I told reception?")
    assert :ok = CallEngine.send_text(current)

    {_destination_provider, destination_request} =
      receive_request_for_prompt("Handle billing requests.")

    assert Enum.map(destination_request.messages, &{&1.role, &1.content}) == [
             {:system, "Handle billing requests."},
             {:user, "Remember invoice 17."},
             {:user, "Please transfer me to billing."},
             {:user, "Can you see what I told reception?"}
           ]
  end

  test "selected history requires and privately retains a bounded transfer reason" do
    plan = compile_plan(transfer_history: %{mode: "selected"})
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    attach_caller(plan, room, caller)

    binding = Map.fetch!(reception.tools, "transfer").transfer
    context = transfer_context(plan, room, caller, reception, "selected-transfer")

    assert {:error, :rejected} =
             Request.new(binding, %{"destination" => "billing"}, context)

    assert {:error, :rejected} =
             Request.new(
               binding,
               %{"destination" => "billing", "reason" => "   "},
               context
             )

    assert {:error, :rejected} =
             Request.new(
               binding,
               %{"destination" => "billing", "reason" => String.duplicate("x", 1_025)},
               context
             )

    reason = "The caller needs help understanding invoice 17."

    assert {:ok, request} =
             Request.new(
               binding,
               %{"destination" => "billing", "reason" => "  #{reason}  "},
               context
             )

    assert request.reason == reason
    refute inspect(request) =~ reason
  end

  test "selected history supplies only destination-readable variables and transfer reason" do
    plan =
      compile_plan(
        transfer_history: %{mode: "selected"},
        selected_variables: true
      )

    caller = Map.fetch!(plan.participants, "caller")

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    attach_caller(plan, room, caller)

    assert :ok =
             CallEngine.send_text(
               send_command(plan, room, caller, "My private reception note must not transfer.")
             )

    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}

    reason = "The caller needs help understanding invoice 17."

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "selected-context-transfer",
               name: "transfer",
               arguments: %{"destination" => "billing", "reason" => reason}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "selected-context-transfer"}},
                   2_000

    current = send_command(plan, room, caller, "Can you help with this invoice?")
    assert :ok = CallEngine.send_text(current)

    {_destination_provider, destination_request} =
      receive_request_for_prompt("Handle billing requests.")

    assert Enum.map(destination_request.messages, &{&1.role, &1.content}) == [
             {:system, "Handle billing requests."},
             {:user, "Can you help with this invoice?"}
           ]

    assert destination_request.model_context == %{
             "call_variables" => %{
               "global_revision" => 0,
               "sections" => %{
                 "order" => %{
                   "revision" => 0,
                   "value" => %{"id" => "invoice-17"}
                 }
               }
             },
             "transfer" => %{"reason" => reason}
           }

    refute inspect(destination_request) =~ reason
    refute inspect(destination_request.model_context) =~ "private-reception-value"
  end

  test "room authority rejects a stale source activation before destination startup" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} = CallEngine.start_call(plan)
    attach_caller(plan, room, caller)

    request = transfer_request(plan, room, caller, reception, "tool-stale-transfer")

    wrong_source = %{request | source_participant_id: billing.participant_id}
    assert {:error, :rejected} = RoomAuthority.transfer(wrong_source)

    stale_request = %{request | source_activation_id: "act_stale"}

    assert {:error, :rejected} = RoomAuthority.transfer(stale_request)
    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)
  end

  test "failed destination preparation leaves the source responsible" do
    plan = compile_plan(billing_model: "test:unavailable")
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

    attach_caller(plan, room, caller)

    first = send_command(plan, room, caller, "Please try billing.")
    assert :ok = CallEngine.send_text(first)
    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "failed-transfer-to-billing",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "failed-transfer-to-billing",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   2_000

    assert_archived_transfer(
      :participant_transfer_started,
      reception,
      caller,
      billing,
      "failed-transfer-to-billing",
      %{}
    )

    assert_archived_transfer(
      :participant_transfer_failed,
      reception,
      caller,
      billing,
      "failed-transfer-to-billing",
      %{
        "cause" => "destination_plan_unavailable",
        "outcome" => "failed",
        "restoration" => "completed"
      }
    )

    reply_to_next_request("The transfer could not be completed.")
    reply_to_next_request("I am still available to help.")

    assert_receive {:vxpipe_event, %TextOutput{text: "I am still available to help."}}, 2_000
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 2_000

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)

    next = send_command(plan, room, caller, "Are you still there?")
    assert :ok = CallEngine.send_text(next)

    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 2_000

    assert [%Message{role: :system, content: "Route callers safely."} | _history] =
             next_request.messages

    assert Enum.any?(next_request.messages, fn message ->
             message.role == :user and message.content == "Are you still there?"
           end)

    assert {:ok, next_response} = ModelResponse.new(text: "Yes.")
    send(next_provider, {:test_agent_runtime_response, {:ok, next_response}})
  end

  test "a total attempt deadline rejects blocked preparation and preserves the source" do
    plan =
      compile_plan(
        billing_model: "test:blocked",
        billing_first_message: %{mode: "fixed", text: "Billing is ready."},
        transfer_timeout_ms: 2_000
      )

    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")
    billing_participant_id = billing.participant_id

    assert {:ok, room} = CallEngine.start_call(plan, archive: archive_options())
    attach_caller(plan, room, caller)

    initial = send_command(plan, room, caller, "Please try billing.")
    assert :ok = CallEngine.send_text(initial)

    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "timed-transfer-to-billing",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_model_preparing, blocked_preparer}, 2_000

    on_exit(fn ->
      send(blocked_preparer, :release_test_agent_runtime_model)
    end)

    duplicate = transfer_request(plan, room, caller, reception, "duplicate-transfer")
    assert {:error, :rejected} = RoomAuthority.transfer(duplicate)

    reply_to_next_request("I am trying that transfer now.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: initial_correlation}},
                   2_000

    assert initial_correlation == initial.correlation_id

    held = send_command(plan, room, caller, "Can you answer something else?")

    assert {:error, %Vxpipe.CallEngine.Error{code: :conversation_held}} =
             CallEngine.send_text(held)

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "timed-transfer-to-billing",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   3_000

    assert_archived_transfer(
      :participant_transfer_started,
      reception,
      caller,
      billing,
      "timed-transfer-to-billing",
      %{}
    )

    assert_archived_transfer(
      :participant_transfer_failed,
      reception,
      caller,
      billing,
      "timed-transfer-to-billing",
      %{
        "cause" => "deadline_elapsed",
        "outcome" => "failed",
        "restoration" => "completed"
      }
    )

    reply_to_next_request("The transfer could not be completed.")

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))
    assert AgentActivationSupervisor.whereis_child(billing.activation_id, :session) == nil

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, billing.participant_id)

    send(blocked_preparer, :release_test_agent_runtime_model)

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "timed-transfer-to-billing"}},
                   100

    refute_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^billing_participant_id,
                      text: "Billing is ready."
                    }},
                   100

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, "Are you still there?"))

    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 2_000

    assert [%Message{role: :system, content: "Route callers safely."} | _history] =
             next_request.messages

    refute Enum.any?(next_request.messages, &(&1.content == held.content))

    assert {:ok, next_response} = ModelResponse.new(text: "Yes.")
    send(next_provider, {:test_agent_runtime_response, {:ok, next_response}})
  end

  test "a destination that exits after preparation cannot commit the transfer" do
    plan =
      compile_plan(
        billing_model: "test:blocked",
        transfer_timeout_ms: 5_000
      )

    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

    attach_caller(plan, room, caller)

    assert :ok =
             CallEngine.send_text(send_command(plan, room, caller, "Please try billing."))

    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "destination-exited-before-commit",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_model_preparing, blocked_preparer}, 2_000

    authority = room_authority(plan)
    %{pending_participant_transfer: %{task: preparation_task}} = :sys.get_state(authority)
    preparation_monitor = Process.monitor(preparation_task.pid)

    assert :ok = :sys.suspend(authority)

    on_exit(fn ->
      try do
        _ = :sys.resume(authority)
      catch
        :exit, _reason -> :ok
      end
    end)

    assert {:ok, scope} = Phase.scope(preparation_task.pid)
    assert scope.authority == authority
    worker_monitor = Process.monitor(scope.preparer.pid)
    send(blocked_preparer, :release_test_agent_runtime_model)
    assert_receive {:DOWN, ^worker_monitor, :process, _worker, :normal}, 2_000

    destination_key =
      {:participant_supervisor, plan.tenant_id, plan.room_id, billing.participant_id}

    assert [{destination_supervisor, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, destination_key)

    destination_monitor = Process.monitor(destination_supervisor)

    assert :ok =
             RoomParticipantSupervisor.stop_participant(
               room.incarnation_id,
               destination_supervisor
             )

    assert_receive {:DOWN, ^destination_monitor, :process, ^destination_supervisor, :shutdown},
                   2_000

    assert :ok = :sys.resume(authority)

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "destination-exited-before-commit",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   2_000

    assert_receive {:DOWN, ^preparation_monitor, :process, _preparation_task, :shutdown}, 2_000

    assert_archived_transfer(
      :participant_transfer_failed,
      reception,
      caller,
      billing,
      "destination-exited-before-commit",
      %{
        "cause" => "destination_media_unavailable",
        "outcome" => "failed",
        "restoration" => "completed"
      }
    )

    refute_receive {:vxpipe_event,
                    %ToolCallCompleted{tool_call_id: "destination-exited-before-commit"}},
                   100

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               billing.participant_id
             )

    reply_to_next_request("The transfer could not be completed.")
  end

  for available? <- [true, false] do
    @restoration_credential_available available?
    test "source speech restoration rechecks credentials when available=#{@restoration_credential_available}" do
      configure_text_to_speech()

      binding = {"tenant-transfer", "deepgram", "default"}

      credentials =
        start_supervised!(
          {Agent, fn -> %{binding => %{"api_key" => "source-private-marker"}} end}
        )

      plan =
        compile_plan(
          billing_model: "test:blocked-unavailable",
          text_to_speech: true
        )

      caller = Map.fetch!(plan.participants, "caller")
      reception = Map.fetch!(plan.participants, "reception")
      billing = Map.fetch!(plan.participants, "billing")

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan,
                 archive: archive_options(),
                 credential_source:
                   {Vxpipe.CallEngine.TestTenantCredentialSource, {:store, self(), credentials}}
               )

      assert_receive {:test_tts_transport_started, source_transport, connection}, 2_000
      assert connection.headers == [{"Authorization", "Token source-private-marker"}]

      TestTextToSpeechTransport.deliver_control(
        source_transport,
        ~s({"type":"Connected","request_id":"initial-source-ready"})
      )

      attach_caller(plan, room, caller)

      assert :ok =
               CallEngine.send_text(send_command(plan, room, caller, "Please try billing."))

      assert_receive {:test_agent_runtime_stream, source_provider, _source_request}, 2_000

      assert {:ok, transfer_call} =
               ToolCall.new(
                 id: "restore-source-after-failure",
                 name: "transfer",
                 arguments: %{"destination" => "billing"}
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
      send(source_provider, {:test_agent_runtime_response, {:ok, response}})

      assert_receive {:test_agent_runtime_model_preparing, blocked_preparer}, 2_000

      authority = room_authority(plan)
      %{text_to_speech_capability: %{pid: source_capability}} = :sys.get_state(authority)
      source_monitor = Process.monitor(source_capability)

      TestTextToSpeechTransport.disconnect(source_transport, :test_disconnect)
      assert_receive {:DOWN, ^source_monitor, :process, ^source_capability, _reason}, 2_000
      assert %{text_to_speech_capability: nil} = :sys.get_state(authority)

      authority_monitor = Process.monitor(authority)

      if @restoration_credential_available do
        Agent.update(credentials, &Map.put(&1, binding, %{"api_key" => "current-private-marker"}))
      else
        Agent.update(credentials, &Map.delete(&1, binding))
      end

      send(blocked_preparer, :release_test_agent_runtime_model)

      if @restoration_credential_available do
        assert_receive {:test_tts_transport_started, restored_transport, restored_connection},
                       2_000

        assert restored_connection.headers == [{"Authorization", "Token current-private-marker"}]

        refute_receive {:vxpipe_event,
                        %ToolCallFailed{tool_call_id: "restore-source-after-failure"}},
                       50

        TestTextToSpeechTransport.deliver_control(
          restored_transport,
          ~s({"type":"Connected","request_id":"restored-source"})
        )

        assert_receive {:vxpipe_event,
                        %ToolCallFailed{
                          tool_call_id: "restore-source-after-failure",
                          name: "transfer",
                          reason: :tool_failed
                        }},
                       2_000

        assert_archived_transfer(
          :participant_transfer_started,
          reception,
          caller,
          billing,
          "restore-source-after-failure",
          %{}
        )

        assert_archived_transfer(
          :participant_transfer_failed,
          reception,
          caller,
          billing,
          "restore-source-after-failure",
          %{
            "cause" => "destination_plan_unavailable",
            "outcome" => "failed",
            "restoration" => "completed"
          }
        )

        %{text_to_speech_capability: %{pid: restored_capability}} = :sys.get_state(authority)
        restored_monitor = Process.monitor(restored_capability)
        TestTextToSpeechTransport.disconnect(restored_transport, :test_disconnect)

        assert_receive {:DOWN, ^restored_monitor, :process, ^restored_capability, _reason}, 2_000
        assert %{text_to_speech_capability: nil} = :sys.get_state(authority)
        refute_receive {:test_tts_transport_started, _third_transport, _connection}, 100
      else
        assert_receive {:DOWN, ^authority_monitor, :process, ^authority,
                        :handoff_recovery_failed},
                       2_000

        refute_receive {:test_tts_transport_started, _, _}

        assert_archived_transfer(
          :participant_transfer_failed,
          reception,
          caller,
          billing,
          "restore-source-after-failure",
          %{
            "cause" => "destination_plan_unavailable",
            "outcome" => "failed",
            "restoration" => "failed"
          }
        )
      end
    end
  end

  test "source restoration stays asynchronous and closes the room when required speech times out" do
    start_counter = :atomics.new(1, [])

    configure_text_to_speech(
      start_counter: start_counter,
      block_after_starts: 1
    )

    plan =
      compile_plan(
        billing_model: "test:blocked-unavailable",
        text_to_speech: true,
        transfer_timeout_ms: 1_000
      )

    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

    assert_receive {:test_tts_transport_started, source_transport, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_transport,
      ~s({"type":"Connected","request_id":"initial-source-ready"})
    )

    attach_caller(plan, room, caller)

    assert :ok =
             CallEngine.send_text(send_command(plan, room, caller, "Please try billing."))

    assert_receive {:test_agent_runtime_stream, source_provider, _source_request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "timed-source-restoration",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_agent_runtime_model_preparing, blocked_preparer}, 2_000

    authority = room_authority(plan)
    %{text_to_speech_capability: %{pid: source_capability}} = :sys.get_state(authority)
    source_monitor = Process.monitor(source_capability)
    TestTextToSpeechTransport.disconnect(source_transport, :test_disconnect)
    assert_receive {:DOWN, ^source_monitor, :process, ^source_capability, _reason}, 2_000

    send(blocked_preparer, :release_test_agent_runtime_model)

    assert_receive {:test_tts_transport_start_blocked, blocked_transport, _connection}, 2_000

    on_exit(fn ->
      send(blocked_transport, :release_test_tts_transport_start)
    end)

    authority_monitor = Process.monitor(authority)
    snapshot = Task.async(fn -> RoomAuthority.snapshot(plan.tenant_id, plan.room_id) end)
    assert {:ok, _snapshot} = Task.yield(snapshot, 250)

    assert_receive {:DOWN, ^authority_monitor, :process, ^authority, :handoff_recovery_failed},
                   2_000

    assert_archived_transfer(
      :participant_transfer_failed,
      reception,
      caller,
      billing,
      "timed-source-restoration",
      %{
        "cause" => "destination_plan_unavailable",
        "outcome" => "failed",
        "restoration" => "timed_out"
      }
    )

    blocked_monitor = Process.monitor(blocked_transport)
    assert_receive {:DOWN, ^blocked_monitor, :process, ^blocked_transport, _reason}, 2_000

    refute_receive {:test_tts_transport_started, _transport, _connection}, 100
  end

  test "agent re-entry keeps identity, refreshes activation, and does not replay its greeting" do
    plan =
      compile_plan(
        billing_first_message: %{mode: "fixed", text: "Billing is ready."},
        billing_transfers: ["reception"],
        reception_transfer_history: %{mode: "last_n_spoken", turns: 1}
      )

    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")
    billing_participant_id = billing.participant_id

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

    attach_caller(plan, room, caller)

    transfer_through_model(
      plan,
      room,
      caller,
      "Please transfer me to billing.",
      "reception",
      "billing",
      "transfer-to-billing"
    )

    _ = RoomAuthority.snapshot(plan.tenant_id, plan.room_id)

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^billing_participant_id,
                      text: "Billing is ready."
                    }},
                   2_000

    transfer_through_model(
      plan,
      room,
      caller,
      "Please send me back to reception.",
      "billing",
      "reception",
      "transfer-to-reception"
    )

    _ = RoomAuthority.snapshot(plan.tenant_id, plan.room_id)

    assert {:ok, reception_snapshot} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               reception.participant_id
             )

    assert reception_snapshot.participant_id == reception.participant_id
    assert AgentActivationSupervisor.whereis_child(reception.activation_id, :session) == nil

    reentry_activation_id = active_activation_id(plan, reception.participant_id)
    refute reentry_activation_id == reception.activation_id
    assert is_pid(AgentActivationSupervisor.whereis_child(reentry_activation_id, :session))
    assert_archive_join(reception.participant_id, reentry_activation_id)

    current = send_command(plan, room, caller, "Can reception continue helping me?")
    assert :ok = CallEngine.send_text(current)

    {provider, request} = receive_request_for_prompt("Route callers safely.")

    assert Enum.map(request.messages, &{&1.role, &1.content}) == [
             {:system, "Route callers safely."},
             {:user, "Please send me back to reception."},
             {:user, "Can reception continue helping me?"}
           ]

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "reentered-reception-transfer",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    source_monitor = monitor_active_participant(plan, reception.participant_id)
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "reentered-reception-transfer",
                      result: %{"destination" => "billing", "status" => "completed"}
                    }},
                   2_000

    assert_receive {:DOWN, ^source_monitor, :process, _source_supervisor, _reason}, 2_000
    _ = RoomAuthority.snapshot(plan.tenant_id, plan.room_id)

    refute_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^billing_participant_id,
                      text: "Billing is ready."
                    }},
                   100
  end

  defp compile_plan(options \\ []) do
    billing_model = Keyword.get(options, :billing_model, "test:scripted")

    billing_first_message =
      Keyword.get(options, :billing_first_message, %{mode: "wait_for_input"})

    billing_transfers = Keyword.get(options, :billing_transfers, [])

    reception_transfer_history =
      Keyword.get(options, :reception_transfer_history, %{mode: "fresh"})

    transfer_timeout_ms = Keyword.get(options, :transfer_timeout_ms, 30_000)
    transfer_history = Keyword.get(options, :transfer_history, %{mode: "fresh"})
    text_to_speech? = Keyword.get(options, :text_to_speech, false)

    {call_variables, initial_variables, reception_permissions, billing_permissions} =
      variable_setup(options)

    assert {:ok, call_spec} =
             CallSpec.new(
               %{
                 schema_version: CallSpec.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 call_variables: call_variables,
                 transfer_policy: %{attempt_timeout_ms: transfer_timeout_ms},
                 participants: %{
                   "caller" => %{
                     type: "human",
                     connection: %{
                       service: "web",
                       mode: "receive",
                       admission: "start_call"
                     }
                   },
                   "reception" => %{
                     type: "agent",
                     prompt: "Route callers safely.",
                     transfer_history: reception_transfer_history,
                     first_message: %{mode: "wait_for_input"},
                     capabilities: agent_capabilities("test:scripted", text_to_speech?),
                     tools: %{},
                     variable_permissions: reception_permissions,
                     transfers: ["billing"]
                   },
                   "billing" => %{
                     type: "agent",
                     description: "A billing specialist",
                     prompt: "Handle billing requests.",
                     transfer_history: transfer_history,
                     first_message: billing_first_message,
                     capabilities: agent_capabilities(billing_model, text_to_speech?),
                     tools: %{},
                     variable_permissions: billing_permissions,
                     transfers: billing_transfers
                   }
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "transfer-call-spec",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "transfer-call-spec", revision: 1},
                 initial_variables: initial_variables,
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-transfer",
               actor_id: "actor-transfer",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{
               host_tools: %{}
             })

    plan
  end

  defp agent_capabilities(model, true) do
    %{
      model_inference: %{provider: "fixture", model: model},
      text_to_speech: %{
        provider: "deepgram",
        model: "flux-test-voice",
        options: %{encoding: "linear16", sample_rate: 48_000}
      }
    }
  end

  defp agent_capabilities(model, false),
    do: %{model_inference: %{provider: "fixture", model: model}}

  defp configure_text_to_speech(transport_options \\ []) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    text_to_speech = [
      providers: %{
        FluxTextToSpeech.Session => [
          enabled: true,
          wire_module: TestTextToSpeechTransport,
          wire_options: Keyword.merge([observer: self()], transport_options),
          maximum_requests: 2
        ]
      }
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :text_to_speech, text_to_speech)
    )
  end

  defp variable_setup(options) do
    if Keyword.get(options, :selected_variables, false) do
      sections = %{
        "order" => %{
          schema: %{
            "type" => "object",
            "properties" => %{"id" => %{"type" => "string"}},
            "additionalProperties" => false
          }
        },
        "reception_private" => %{
          schema: %{
            "type" => "object",
            "properties" => %{"note" => %{"type" => "string"}},
            "additionalProperties" => false
          }
        }
      }

      initial_variables = %{
        "order" => %{"id" => "invoice-17"},
        "reception_private" => %{"note" => "private-reception-value"}
      }

      {
        %{sections: sections},
        initial_variables,
        %{"reception_private" => ["read"]},
        %{"order" => ["read"]}
      }
    else
      {%{sections: %{}}, %{}, %{}, %{}}
    end
  end

  defp attach_caller(plan, room, caller) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "connection-transfer",
               deadline: future_deadline()
             )

    assert {:ok, attachment} = CallEngine.attach_connection(command)
    Vxpipe.CallEngine.TestCallStartup.await_ready(attachment)
  end

  defp send_command(plan, room, caller, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "connection-transfer",
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    command
  end

  defp transfer_request(plan, room, caller, source, tool_call_id) do
    context = transfer_context(plan, room, caller, source, tool_call_id)

    binding = Map.fetch!(source.tools, "transfer").transfer

    assert {:ok, request} =
             Request.new(binding, %{"destination" => "billing"}, context)

    request
  end

  defp transfer_context(plan, room, caller, source, tool_call_id) do
    %Context{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      agent_participant_id: source.participant_id,
      source_participant_id: caller.participant_id,
      connection_id: "connection-transfer",
      command_id: "command-#{tool_call_id}",
      correlation_id: "turn-#{tool_call_id}",
      agent_request_id: "request-#{tool_call_id}",
      tool_call_id: tool_call_id,
      audio_response: false
    }
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp receive_request_for_prompt(prompt) do
    receive do
      {:test_agent_runtime_stream, provider,
       %{messages: [%Message{role: :system, content: ^prompt} | _history]} = request} ->
        {provider, request}

      {:test_agent_runtime_stream, provider, _stale_source_request} ->
        assert {:ok, response} = ModelResponse.new(text: "Transfer in progress.")
        send(provider, {:test_agent_runtime_response, {:ok, response}})
        receive_request_for_prompt(prompt)
    after
      2_000 -> flunk("timed out waiting for agent prompt #{inspect(prompt)}")
    end
  end

  defp transfer_through_model(
         plan,
         room,
         caller,
         input,
         source_call_spec_key,
         destination,
         tool_call_id
       ) do
    source = Map.fetch!(plan.participants, source_call_spec_key)
    source_monitor = monitor_active_participant(plan, source.participant_id)

    assert :ok = CallEngine.send_text(send_command(plan, room, caller, input))
    {provider, _request} = receive_request_for_prompt(source.prompt)

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: tool_call_id,
               name: "transfer",
               arguments: %{"destination" => destination}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: ^tool_call_id,
                      result: %{"destination" => ^destination, "status" => "completed"}
                    }},
                   2_000

    assert_receive {:DOWN, ^source_monitor, :process, _source_supervisor, _reason}, 2_000
  end

  defp monitor_active_participant(plan, participant_id) do
    key = {:participant_supervisor, plan.tenant_id, plan.room_id, participant_id}

    assert [{participant_supervisor, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key)

    Process.monitor(participant_supervisor)
  end

  defp room_authority(plan) do
    assert [{authority, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {plan.tenant_id, plan.room_id}
             )

    authority
  end

  defp active_activation_id(plan, participant_id) do
    key = {:participant_supervisor, plan.tenant_id, plan.room_id, participant_id}

    assert [{participant_supervisor, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key)

    assert {:agent_activation, activation_supervisor, :supervisor, [AgentActivationSupervisor]} =
             List.keyfind(Supervisor.which_children(participant_supervisor), :agent_activation, 0)

    assert [{:agent_activation, activation_id, :supervisor}] =
             Registry.keys(Vxpipe.CallEngine.RoomRegistry, activation_supervisor)

    activation_id
  end

  defp assert_archive_join(participant_id, activation_id) do
    receive do
      {:test_archive_fact,
       %Fact{
         kind: :participant_joined,
         participant_id: ^participant_id,
         activation_id: ^activation_id
       }} ->
        :ok

      {:test_archive_fact, %Fact{}} ->
        assert_archive_join(participant_id, activation_id)
    after
      2_000 ->
        flunk(
          "timed out waiting for archived participant join #{participant_id} / #{activation_id}"
        )
    end
  end

  defp assert_archived_transfer(
         kind,
         source,
         caller,
         destination,
         tool_call_id,
         additional_payload
       ) do
    receive do
      {:test_archive_fact,
       %Fact{
         kind: ^kind,
         participant_id: source_participant_id,
         activation_id: source_activation_id,
         source_participant_id: caller_participant_id,
         tool_call_id: ^tool_call_id,
         public_sequence: nil,
         payload: payload
       }} ->
        assert source_participant_id == source.participant_id
        assert source_activation_id == source.activation_id
        assert caller_participant_id == caller.participant_id

        assert payload ==
                 Map.merge(
                   %{
                     "destination_call_spec_key" => destination.call_spec_key,
                     "destination_participant_id" => destination.participant_id,
                     "source_call_spec_key" => source.call_spec_key
                   },
                   additional_payload
                 )

      {:test_archive_fact, %Fact{}} ->
        assert_archived_transfer(
          kind,
          source,
          caller,
          destination,
          tool_call_id,
          additional_payload
        )
    after
      2_000 -> flunk("timed out waiting for archived #{kind} fact")
    end
  end

  defp archive_options do
    [
      enabled: true,
      writer: {TestCollectingArchiveWriter, self()},
      maximum_pending_facts: 64,
      retry_delay_ms: 5,
      drain_timeout_ms: 1_000
    ]
  end

  defp reply_to_next_request(text) do
    assert_receive {:test_agent_runtime_stream, provider, _request}, 2_000
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp unique_id(prefix),
    do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
