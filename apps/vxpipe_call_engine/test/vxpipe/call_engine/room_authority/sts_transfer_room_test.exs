defmodule Vxpipe.CallEngine.RoomAuthority.STSTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomAuthority}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TestCallStartup
  alias Vxpipe.CallEngine.TestGPTLiveTransport
  alias Vxpipe.CallEngine.TestTenantCredentialSource
  alias Vxpipe.CallEngine.TestTransferConnection
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession
  alias Vxpipe.Providers.OpenAI.GPTLiveSession

  @tenant "tenant-sts-transfer"

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(
        :fixture,
        {CallEngine.TestSelectiveAgentRuntimeModelProvider, [owner: self()]}
      )

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
    :ok
  end

  test "compiled Morse transfer commits and tears down the source session" do
    context = room("test:scripted")
    provider = context.provider
    capability = context.capability
    authority = context.authority
    provider_monitor = Process.monitor(provider)
    capability_monitor = Process.monitor(capability)
    task = transfer(context)

    assert {:ok, %{"status" => "completed", "destination" => "billing"}} =
             Task.await(task, 5_000)

    send(context.authority, {
      :vxpipe_platform_effect,
      context.capability,
      transfer_context(context),
      :participant_transfer_committed
    })

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _}, 5_000
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}, 5_000
    _ = :sys.get_state(authority)
  end

  test "failed compiled Morse transfer releases the original session" do
    context = room("test:unavailable")
    provider_monitor = Process.monitor(context.provider)
    task = transfer(context)

    assert {:error, :unavailable} = Task.await(task, 5_000)
    assert Session.provider(:sys.get_state(context.capability).session) == context.provider
    refute_received {:DOWN, ^provider_monitor, :process, _, _}
    refute :sys.get_state(context.provider).held?
    assert_source_resumed(context)
  end

  test "an STS transfer tool call commits and tears down its compiled source" do
    context = room("test:scripted")
    provider_monitor = Process.monitor(context.provider)
    capability_monitor = Process.monitor(context.capability)

    assert :ok =
             Vxpipe.CallEngine.Capability.SpeechToSpeech.push_text(
               context.capability,
               ~s(TOOL transfer {"destination":"billing"})
             )

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{name: "transfer"}},
                   2_000

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallCompleted{name: "transfer"}},
                   5_000

    assert_receive {:DOWN, ^provider_monitor, :process, _, _}, 5_000
    assert_receive {:DOWN, ^capability_monitor, :process, _, _}, 5_000
  end

  test "a failed STS transfer tool call releases the same compiled session" do
    context = room("test:unavailable")
    provider_monitor = Process.monitor(context.provider)

    assert :ok =
             Vxpipe.CallEngine.Capability.SpeechToSpeech.push_text(
               context.capability,
               ~s(TOOL transfer {"destination":"billing"})
             )

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{name: "transfer"}},
                   2_000

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallFailed{name: "transfer"}},
                   5_000

    assert Session.provider(:sys.get_state(context.capability).session) == context.provider
    refute_received {:DOWN, ^provider_monitor, :process, _, _}
    refute :sys.get_state(context.provider).held?
    assert_source_resumed(context)
  end

  test "a GPT-Live provider-originated transfer commits and tears down its compiled source" do
    context = gpt_live_room("test:scripted")
    provider = context.provider
    capability = context.capability
    authority = context.authority
    provider_monitor = Process.monitor(provider)
    capability_monitor = Process.monitor(capability)
    wire = context.wire

    push_caller_audio(context)
    deliver_transfer(context.wire)

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{name: "transfer"}},
                   2_000

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.mute", "event_id" => event_id}},
                   2_000

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.input_audio.muted",
      "client_event_id" => event_id
    })

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.unmute", "event_id" => unmute_id}},
                   5_000

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.input_audio.unmuted",
      "client_event_id" => unmute_id
    })

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallCompleted{name: "transfer"}},
                   5_000

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _}, 5_000
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}, 5_000
    _ = :sys.get_state(authority)
  end

  test "a failed GPT-Live provider-originated transfer releases the same socket" do
    context = gpt_live_room("test:unavailable")
    provider_monitor = Process.monitor(context.provider)
    authority = context.authority
    authority_monitor = Process.monitor(authority)
    wire = context.wire

    push_caller_audio(context)
    deliver_transfer(context.wire)

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{name: "transfer"}},
                   2_000

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.mute", "event_id" => mute_id}},
                   2_000

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.input_audio.muted",
      "client_event_id" => mute_id
    })

    assert_receive {:test_gpt_live_control, ^wire,
                    %{"type" => "session.input_audio.unmute", "event_id" => unmute_id}},
                   5_000

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.input_audio.unmuted",
      "client_event_id" => unmute_id
    })

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallFailed{name: "transfer"}},
                   5_000

    assert_receive {:test_gpt_live_control, ^wire,
                    %{
                      "type" => "response.item.create",
                      "item" => %{
                        "type" => "function_call_output",
                        "call_id" => "t1",
                        "output" => output
                      }
                    }},
                   5_000

    assert %{"error" => "tool_failed"} = JSON.decode!(output)

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "response.create"}}, 5_000

    assert Session.provider(:sys.get_state(context.capability).session) == context.provider
    refute_received {:DOWN, ^provider_monitor, :process, _, _}
    refute_received {:DOWN, ^authority_monitor, :process, _, _}
    refute :sys.get_state(context.provider).held?
    assert_gpt_live_resumed(context)
    _ = :sys.get_state(authority)
  end

  defp room(destination_model) do
    configure_provider()
    speech = %{provider: "morse", model: "morse-duplex", options: %{}}

    source = %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer the caller.",
          tools: %{},
          transfers: ["billing"],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{speech_to_speech: speech}
        },
        "billing" => %{
          type: "agent",
          prompt: "Handle billing.",
          tools: %{},
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{
            model_inference: %{provider: "fixture", model: destination_model}
          }
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-transfer", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-transfer", revision: 1}, transport: %{type: "web"}},
               tenant_id: @tenant,
               actor_id: "actor-sts-transfer"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    caller = Map.fetch!(plan.participants, "caller")
    agent = Map.fetch!(plan.participants, "assistant")
    destination = Map.fetch!(plan.participants, "billing")
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, opened} = TestCallStartup.start_call(plan)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: opened.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    track = %{
      track_id: "microphone",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1
    }

    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink, input_track: track)

    TestCallStartup.await_ready(plan.room_id)

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(
        opened.incarnation_id,
        agent.participant_id
      )

    assert is_pid(capability)

    %{
      plan: plan,
      opened: opened,
      command: command,
      authority: authority,
      caller: caller,
      agent: agent,
      destination: destination,
      capability: capability,
      provider: Session.provider(:sys.get_state(capability).session)
    }
  end

  defp transfer(context) do
    request = %Request{
      tenant_id: context.plan.tenant_id,
      room_id: context.plan.room_id,
      incarnation_id: context.opened.incarnation_id,
      source_call_spec_key: "assistant",
      source_participant_id: context.agent.participant_id,
      source_activation_id: context.agent.activation_id,
      source_capability: context.capability,
      caller_participant_id: context.caller.participant_id,
      connection_id: context.command.connection_id,
      command_id: "sts-transfer-command",
      correlation_id: "sts-transfer-turn",
      tool_call_id: "sts-transfer-tool",
      destination_call_spec_key: "billing",
      destination_participant_id: context.destination.participant_id,
      reason: nil
    }

    supervisor = start_supervised!({Task.Supervisor, []})
    Task.Supervisor.async(supervisor, fn -> RoomAuthority.transfer(request) end)
  end

  defp transfer_context(context) do
    %ToolContext{
      tenant_id: context.plan.tenant_id,
      room_id: context.plan.room_id,
      incarnation_id: context.opened.incarnation_id,
      agent_participant_id: context.agent.participant_id,
      source_participant_id: context.caller.participant_id,
      connection_id: context.command.connection_id,
      command_id: "sts-transfer-command",
      correlation_id: "sts-transfer-turn",
      tool_call_id: "sts-transfer-tool"
    }
  end

  defp configure_provider do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)
    speech = [providers: %{DuplexSTSSession => [enabled: true]}]

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(settings, :speech_to_speech, speech)
    )
  end

  defp assert_source_resumed(context) do
    assert :ok = Vxpipe.CallEngine.Capability.SpeechToSpeech.push_text(context.capability, "HI")
    _ = :sys.get_state(context.provider)
  end

  defp gpt_live_room(destination_model) do
    configure_openai_provider()
    speech = %{provider: "openai", model: "gpt-live-1", options: %{}}

    source = %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer the caller.",
          tools: %{},
          transfers: ["billing"],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{speech_to_speech: speech}
        },
        "billing" => %{
          type: "agent",
          prompt: "Handle billing.",
          tools: %{},
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{
            model_inference: %{provider: "fixture", model: destination_model}
          }
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-transfer", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-transfer", revision: 1}, transport: %{type: "web"}},
               tenant_id: @tenant,
               actor_id: "actor-sts-transfer"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    caller = Map.fetch!(plan.participants, "caller")
    agent = Map.fetch!(plan.participants, "assistant")
    destination = Map.fetch!(plan.participants, "billing")
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    bindings = %{{@tenant, "openai", "default"} => %{"api_key" => "synthetic-test-key"}}

    assert {:ok, opened} =
             TestCallStartup.start_call(plan,
               credential_source: {TestTenantCredentialSource, {self(), bindings}}
             )

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    observer = self()

    :sys.replace_state(authority, fn state ->
      runtime = state.speech_to_speech_runtime

      private =
        Keyword.merge(runtime.provider_private,
          wire_module: TestGPTLiveTransport,
          wire_options: [observer: observer]
        )

      %{state | speech_to_speech_runtime: %{runtime | provider_private: private}}
    end)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: opened.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    track = %{
      track_id: "microphone",
      codec: :linear16,
      sample_rate: 24_000,
      channels: 1
    }

    assert {:ok, attachment} = TestTransferConnection.attach(command, sink, input_track: track)

    assert_receive {:test_gpt_live_started, wire, _connection}, 5_000

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"}}, 5_000

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.started",
      "session" => %{"id" => "s"}
    })

    TestCallStartup.await_ready(plan.room_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(
        opened.incarnation_id,
        agent.participant_id
      )

    assert is_pid(capability)

    %{
      plan: plan,
      opened: opened,
      command: command,
      attachment: attachment,
      authority: authority,
      caller: caller,
      agent: agent,
      destination: destination,
      capability: capability,
      provider: Session.provider(:sys.get_state(capability).session),
      wire: wire
    }
  end

  defp push_caller_audio(context, sequence \\ 0) do
    wire = context.wire

    frame = %Vxpipe.CallEngine.Media.AudioFrame{
      tenant_id: context.command.tenant_id,
      room_id: context.command.room_id,
      incarnation_id: context.command.incarnation_id,
      participant_id: context.command.participant_id,
      connection_id: context.command.connection_id,
      track_id: "microphone",
      codec: :linear16,
      sample_rate: 24_000,
      channels: 1,
      sequence_number: sequence,
      timestamp: sequence * 160,
      payload: <<1, 0>>,
      received_at: System.monotonic_time(:millisecond)
    }

    assert :ok =
             TestTransferConnection.run(context.command, fn ->
               CallEngine.push_speech_to_speech_audio(context.attachment, frame)
             end)

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}},
                   2_000

    _ = :sys.get_state(context.provider)
  end

  defp assert_gpt_live_resumed(context) do
    push_caller_audio(context, 1)
  end

  defp deliver_transfer(wire) do
    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "session.delegation.created",
      "delegation" => %{"id" => "d1", "target" => "responses", "response_id" => "r1"}
    })

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "response.event",
      "delegation_id" => "d1",
      "event" => %{
        "type" => "response.output_item.done",
        "item" => %{
          "type" => "function_call",
          "status" => "completed",
          "call_id" => "t1",
          "name" => "transfer",
          "arguments" => ~s({"destination":"billing"})
        }
      }
    })

    TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => "response.event",
      "delegation_id" => "d1",
      "event" => %{"type" => "response.completed", "response" => %{"id" => "r1"}}
    })
  end

  defp configure_openai_provider do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)
    speech = [providers: %{GPTLiveSession => [enabled: true]}]

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(settings, :speech_to_speech, speech)
    )
  end
end
