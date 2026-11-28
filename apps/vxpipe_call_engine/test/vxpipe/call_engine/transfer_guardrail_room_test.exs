defmodule Vxpipe.CallEngine.TransferGuardrailRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Archive.Fact

  alias Vxpipe.CallEngine.{
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    TestCallStartup,
    TestCollectingArchiveWriter,
    TestSelectiveAgentRuntimeModelProvider,
    TestTenantCredentialSource
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

  @tenant "tenant-transfer-guardrails"
  @actor "actor-transfer-guardrails"

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  defp configure(scores_owner, credential_bindings) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    configure_text_to_speech()

    plug = fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))
      send(scores_owner, {:decisions_http, self(), body["input"], body["questions"]})

      receive do
        {:decisions_scores, scores} ->
          Req.Test.json(conn, %{
            "model" => "gpt-6-luna",
            "answers" =>
              Enum.map(scores, fn {name, probability} ->
                %{"name" => name, "type" => "predicate", "probability" => probability}
              end)
          })
      after
        5_000 ->
          Req.Test.json(conn, %{"model" => "gpt-6-luna", "answers" => []})
      end
    end

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.merge(
        implementation: :agent_runtime,
        fixture: {TestSelectiveAgentRuntimeModelProvider, [owner: scores_owner]},
        decisions_http_plug: plug
      )

    # Re-read: configure_text_to_speech/0 already wrote :text_to_speech above.
    settings =
      Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    settings =
      settings
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(
        :credential_source,
        {TestTenantCredentialSource, {scores_owner, credential_bindings}}
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)
    :ok
  end

  defp credential_bindings do
    %{
      {@tenant, "openai", "policy"} => %{"api_key" => "synthetic-policy-key"},
      {@tenant, "deepgram", "default"} => %{"api_key" => "synthetic-tts-key"}
    }
  end

  defp configure_text_to_speech do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    text_to_speech = [
      providers: %{
        Vxpipe.Providers.Deepgram.TTSSession => [
          enabled: true,
          wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
          wire_options: [observer: self(), ready_on_start: true],
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

  defp compile_plan(required_answer, second_sender? \\ false) do
    source = %{
      schema_version: "20261128.01",
      name: "Transfer guardrails",
      incoming_call: %{caller: "caller", handled_by: "reception"},
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "default"},
          decisions: %{provider: "openai", model: "gpt-6-luna", credential_name: "policy"}
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          description: "Caller",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          description: "Reception",
          prompt: "Route callers safely.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{
            model_inference: %{provider: "fixture", model: "default"},
            text_to_speech: %{
              provider: "deepgram",
              model: "flux-test-voice",
              options: %{encoding: "linear16", sample_rate: 48_000}
            }
          },
          tools: %{},
          transfers: ["billing"],
          guardrails: %{
            after_turn: [
              %{
                "id" => "polite",
                "question" => "Is the response polite?",
                "required_answer" => "yes"
              }
            ],
            before_outgoing_transfer: [
              %{
                "id" => "wrong_department",
                "question" => "Is the requested destination unrelated to the caller's issue?",
                "required_answer" => required_answer,
                "response" => "Ask which department the caller needs."
              }
            ]
          }
        },
        "billing" => %{
          type: "agent",
          description: "Billing",
          prompt: "Handle billing.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }

    source =
      if second_sender? do
        reception = source.participants["reception"]
        [rule] = reception.guardrails.before_outgoing_transfer

        second = %{
          reception
          | description: "Second receiver",
            transfers: ["billing"],
            guardrails: %{before_outgoing_transfer: [%{rule | "required_answer" => "yes"}]}
        }

        source
        |> put_in([:participants, "reception", :transfers], ["billing", "second"])
        |> put_in([:participants, "second"], second)
      else
        source
      end

    assert {:ok, call_spec} =
             CallSpec.new(source, resource_id: "transfer-guardrails", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "transfer-guardrails", revision: 1}, transport: %{type: "web"}},
               tenant_id: @tenant,
               actor_id: @actor,
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})
    plan
  end

  test "a matched transfer policy blocks the handoff and repairs the model" do
    configure(self(), credential_bindings())
    plan = compile_plan("no")
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")

    assert {:ok, room} = TestCallStartup.start_call(plan, archive: archive_options())

    source_activation = activation_supervisor(plan, reception)
    source_monitor = Process.monitor(source_activation)

    attach_caller(plan, room, caller)
    first = transfer_command(plan, room, caller, "Please transfer me to billing.")
    assert :ok = CallEngine.send_text(first)

    # The model proposes speech plus a transfer in one round.
    assert_receive {:test_agent_runtime_stream, provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "transfer-1",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} =
             ModelResponse.new(text: "I will transfer you now.", tool_calls: [transfer_call])

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    # Joint admission issues both checks; the after check passes while the
    # transfer check blocks on the matched policy.
    answer_decisions(%{"polite" => 0.9, "wrong_department" => 0.9})
    answer_decisions(%{"polite" => 0.9, "wrong_department" => 0.9})

    # The model receives private repair with the authored transfer line only.
    assert_receive {:test_agent_runtime_stream, repair_provider, repair_request}, 2_000
    envelope = repair_envelope(repair_request)
    assert envelope["type"] == "guardrail_failure"

    assert envelope["failures"] == [
             %{
               "event" => "before_outgoing_transfer",
               "messages" => ["Ask which department the caller needs."]
             }
           ]

    # The blocked transfer never submits: the rewrite is checked, delivered,
    # and the source stays active with no handoff.
    assert {:ok, repair_response} = ModelResponse.new(text: "Which department do you need?")
    send(repair_provider, {:test_agent_runtime_response, {:ok, repair_response}})

    answer_decisions(%{"polite" => 0.9})

    # Only the checked replacement reaches the caller: its text is
    # delivered while the denied transfer stays silent and unexecuted.
    assert_receive {:vxpipe_event, %TextOutput{text: "Which department do you need?"}}, 5_000
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 5_000

    refute_received {:vxpipe_event, %ToolCallCompleted{name: "transfer"}}
    refute_received {:test_archive_fact, %Fact{kind: :participant_transfer_started}}
    refute_received {:DOWN, ^source_monitor, :process, ^source_activation, _reason}

    # The source is still responsive: a later turn gets a fresh model round.
    repair_command = transfer_command(plan, room, caller, "Actually never mind.")
    assert :ok = CallEngine.send_text(repair_command)
    assert_receive {:test_agent_runtime_stream, _provider, _followup}, 2_000
  end

  test "a passing transfer check commits exactly one handoff" do
    configure(self(), credential_bindings())
    plan = compile_plan("no")
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} = TestCallStartup.start_call(plan, archive: archive_options())

    source_activation = activation_supervisor(plan, reception)
    source_monitor = Process.monitor(source_activation)

    attach_caller(plan, room, caller)
    first = transfer_command(plan, room, caller, "Please transfer me to billing.")
    assert :ok = CallEngine.send_text(first)

    assert_receive {:test_agent_runtime_stream, provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "transfer-2",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} =
             ModelResponse.new(text: "I will transfer you now.", tool_calls: [transfer_call])

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    answer_decisions(%{"polite" => 0.9, "wrong_department" => 0.05})
    answer_decisions(%{"polite" => 0.9, "wrong_department" => 0.05})

    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "transfer-2"}}, 5_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{tool_call_id: "transfer-2", name: "transfer"}},
                   5_000

    refute_received {:vxpipe_event, %ToolCallCompleted{tool_call_id: "transfer-2"}}
    assert_receive {:DOWN, ^source_monitor, :process, ^source_activation, _reason}, 2_000

    assert_archived_transfer(
      :participant_transfer_started,
      reception,
      caller,
      billing,
      "transfer-2"
    )
  end

  test "opposite required answers decide the same destination differently" do
    configure(self(), credential_bindings())

    # Same question, same score, opposite required answers.
    blocking_plan = compile_plan("no")
    passing_plan = compile_plan("yes")

    assert {:ok, _} = run_transfer_attempt(blocking_plan, "transfer-3", 0.9, :blocked)
    assert {:ok, _} = run_transfer_attempt(passing_plan, "transfer-4", 0.9, :passed)
  end

  test "successive senders apply their own policy to the same target in one compiled call" do
    configure(self(), credential_bindings())
    plan = compile_plan("no", true)
    caller = plan.participants["caller"]
    first = plan.participants["reception"]
    second = plan.participants["second"]
    target = plan.participants["billing"]
    assert {:ok, room} = TestCallStartup.start_call(plan, archive: archive_options())
    attach_caller(plan, room, caller)

    propose_silent_transfer(plan, room, caller, first, target, "declined", 0.9)
    assert_receive {:test_agent_runtime_stream, repair, %{tools: []}}, 2_000
    refute_received {:test_archive_fact, %Fact{kind: :participant_transfer_started}}
    {:ok, reply} = ModelResponse.new(text: "Which department do you need?")
    send(repair, {:test_agent_runtime_response, {:ok, reply}})
    answer_decisions(%{"polite" => 0.9})
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}, 2_000

    propose_silent_transfer(plan, room, caller, first, second, "intermediate", 0.05)
    assert_archived_transfer(:participant_transfer_started, first, caller, second, "intermediate")
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "intermediate"}}, 2_000
    propose_silent_transfer(plan, room, caller, second, target, "accepted", 0.9)
    assert_archived_transfer(:participant_transfer_started, second, caller, target, "accepted")
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "accepted"}}, 2_000
    refute_received {:decisions_http, _, _, _}
    refute_received {:vxpipe_event, %ToolCallCompleted{tool_call_id: "declined"}}
  end

  defp propose_silent_transfer(plan, room, caller, source, destination, invocation, score) do
    command =
      transfer_command(plan, room, caller, "Please connect me to " <> destination.call_spec_key)

    assert :ok = CallEngine.send_text(%{command | audio_response: false})
    command_id = command.id

    assert_receive {:test_agent_runtime_stream, model,
                    %{correlation: %{command_id: ^command_id}}},
                   2_000

    {:ok, call} =
      ToolCall.new(
        id: invocation,
        name: "transfer",
        arguments: %{"destination" => destination.call_spec_key}
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(model, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:decisions_http, http, input, [%{"name" => "wrong_department"}]}, 2_000
    packet = JSON.decode!(input)
    assert packet["participant"] == source.participant_id
    assert packet["current"]["destination"] == destination.call_spec_key

    refute_received {:test_archive_fact,
                     %Fact{kind: :participant_transfer_started, tool_call_id: ^invocation}}

    send(http, {:decisions_scores, %{"wrong_department" => score}})
  end

  defp run_transfer_attempt(plan, tool_call_id, score, expectation) do
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    billing = Map.fetch!(plan.participants, "billing")

    assert {:ok, room} = TestCallStartup.start_call(plan, archive: archive_options())

    source_activation = activation_supervisor(plan, reception)
    source_monitor = Process.monitor(source_activation)

    attach_caller(plan, room, caller)
    assert :ok = CallEngine.send_text(transfer_command(plan, room, caller, "Transfer me."))

    assert_receive {:test_agent_runtime_stream, provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: tool_call_id,
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} =
             ModelResponse.new(text: "Moving you now.", tool_calls: [transfer_call])

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    answer_decisions(%{"polite" => 0.9, "wrong_department" => score})
    answer_decisions(%{"polite" => 0.9, "wrong_department" => score})

    case expectation do
      :blocked ->
        assert_receive {:test_agent_runtime_stream, _provider, repair_request}, 2_000
        assert repair_envelope(repair_request)["failures"] != []
        refute_received {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^tool_call_id}}
        {:ok, :blocked}

      :passed ->
        assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^tool_call_id}}, 2_000
        assert_receive {:DOWN, ^source_monitor, :process, ^source_activation, _}, 2_000

        assert_archived_transfer(
          :participant_transfer_started,
          reception,
          caller,
          billing,
          tool_call_id
        )

        {:ok, :passed}
    end
  end

  # Answers one pending Decisions HTTP call by question name. Each joint
  # admission issues one batched call per event; callers answer every
  # expected call explicitly so missing evaluations fail loudly.
  defp answer_decisions(scores) do
    receive do
      {:decisions_http, plug, _input, questions} ->
        send(plug, {:decisions_scores, Map.take(scores, Enum.map(questions, & &1["name"]))})
    after
      2_000 -> flunk("timed out waiting for a decisions check")
    end
  end

  defp repair_envelope(request) do
    content =
      request.messages
      |> Enum.find_value(fn
        %Message{content: text} when is_binary(text) ->
          if String.contains?(text, "guardrail_failure"), do: text, else: nil

        _message ->
          nil
      end)

    case content do
      nil -> flunk("repair request carried no guardrail failure envelope")
      text -> text |> extract_json() |> JSON.decode!()
    end
  end

  defp extract_json(content) do
    case :binary.match(content, "{") do
      {start, _} -> String.slice(content, start..-1//1)
      :nomatch -> flunk("no JSON object in repair message")
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
    TestCallStartup.await_ready(attachment)
  end

  defp transfer_command(plan, room, caller, content) do
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

  defp activation_supervisor(_plan, participant) do
    key = {:agent_activation, participant.activation_id, :supervisor}

    assert [{supervisor, _value}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key)

    supervisor
  end

  defp assert_archived_transfer(kind, source, caller, destination, tool_call_id) do
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

        assert payload == %{
                 "destination_call_spec_key" => destination.call_spec_key,
                 "destination_participant_id" => destination.participant_id,
                 "source_call_spec_key" => source.call_spec_key
               }
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

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 30, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
