defmodule Vxpipe.CallEngine.ToolContractRoom do
  @moduledoc "Compiled-call fixtures for the common tool contract; only model input differs."

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, RemoteMCPFixture, TestCallStartup}
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.{DuplexSTSSession, STSSession}

  def configure!(limits \\ []) do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)
    observer = self()
    model = start_supervised!({Task, fn -> model_loop(observer) end})

    settings =
      original
      |> Keyword.put(:speech_to_speech,
        providers: %{STSSession => [enabled: true], DuplexSTSSession => [enabled: true]}
      )
      |> Keyword.update!(:agent_runtime, fn settings ->
        settings
        |> Keyword.merge(limits)
        |> Keyword.put(:fixture, {CallEngine.TestAgentRuntimeModelProvider, [owner: model]})
      end)

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
  end

  def start!(path, mode, options \\ []) do
    observer = self()
    result = %{"content" => [%{"type" => "text", "text" => "APPOINTMENT FOUND"}]}
    response = Keyword.get(options, :response, {:ok, result})

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [{:wait, observer, response}], invocations: []} end},
        id: make_ref()
      )

    {catalog, _binding} =
      RemoteMCPFixture.binding!(client, observer, "contract-private-credential")

    store = RemoteMCPFixture.source!(catalog)
    plan = compile!(store, path, mode)
    before = System.monotonic_time(:microsecond)

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: CallEngine.TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: CallEngine.TestRemoteMCPProtocolClient
             )

    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: observer}, id: make_ref())

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "contract-source",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} =
             TestTransferConnection.attach(command, sink,
               input_track: %{
                 track_id: "microphone",
                 codec: :linear16,
                 sample_rate: 16_000,
                 channels: 1
               }
             )

    TestCallStartup.await_ready(plan.room_id)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    capability =
      CallEngine.RoomCapabilitySupervisor.whereis_speech_to_speech(
        room.incarnation_id,
        agent.participant_id
      )

    registry =
      if path == :llm,
        do:
          CallEngine.AgentActivationSupervisor.whereis_child(
            agent.activation_id,
            :invocation_registry
          ),
        else: Tree.invocation_registry(capability)

    assert_receive {:test_remote_mcp_open_options, key, configuration}, 1_000

    assert {:ok, connection} =
             Vxpipe.MCP.Connections.lookup(key, owner: Keyword.fetch!(configuration, :owner))

    %{
      transport: if(path == :llm, do: :text, else: :native),
      path: path,
      plan: plan,
      room: room,
      command: command,
      capability: capability,
      registry: registry,
      authority: authority,
      client: client,
      result: result,
      sink: sink,
      mcp_session: Vxpipe.MCP.Connection.client(connection),
      startup_us: System.monotonic_time(:microsecond) - before
    }
  end

  def invoke(context, name, arguments), do: invoke_many(context, [{name, arguments}])

  def replayable!(%{transport: :text} = context, name, arguments) do
    text =
      "TOOLS " <>
        JSON.encode!([
          %{
            "id" => CallEngine.Id.generate(:tool_attempt),
            "name" => name,
            "arguments" => arguments
          }
        ])

    assert :ok = input(context, text)
    {:text, text}
  end

  def replayable!(%{transport: :native} = context, name, arguments) do
    capability = context.capability
    :erlang.trace(capability, true, [:send])
    assert [:ok] = invoke(context, name, arguments)

    assert_receive {:trace, ^capability, :send,
                    {:vxpipe_sts_tool_event, ^capability, _, _} = message, _},
                   1_000

    :erlang.trace(capability, false, [:send])
    {:native, message}
  end

  def replay!(context, {:text, text}) do
    assert :ok = input(context, text)
    room_id = context.plan.room_id

    assert_receive {:contract_model_rejection, ^room_id,
                    %{"status" => "rejected", "reason" => "rejected"}},
                   1_000
  end

  def replay!(context, {:native, {:vxpipe_sts_tool_event, capability, agent, evidence}}) do
    previous = :sys.get_state(context.authority).sts_tool_sequence
    event = %{evidence.event | sequence: previous + 1}

    send(
      context.authority,
      {:vxpipe_sts_tool_event, capability, agent, %{evidence | event: event}}
    )

    assert :sys.get_state(context.authority).sts_tool_sequence > previous
    :ok
  end

  def invoke_many(%{transport: :native} = context, calls) do
    Enum.map(calls, fn {name, arguments} ->
      SpeechToSpeech.push_text(context.capability, "TOOL #{name} #{JSON.encode!(arguments)}")
    end)
  end

  def invoke_many(%{transport: :text} = context, calls) do
    encoded =
      Enum.map(calls, fn {name, arguments} -> %{"name" => name, "arguments" => arguments} end)

    [input(context, "TOOLS " <> JSON.encode!(encoded))]
  end

  def input(%{transport: :native} = context, text),
    do: SpeechToSpeech.push_text(context.capability, text)

  def input(%{transport: :text} = context, text) do
    attach = context.command

    assert {:ok, command} =
             SendText.new(
               tenant_id: attach.tenant_id,
               actor_id: attach.actor_id,
               room_id: attach.room_id,
               incarnation_id: attach.incarnation_id,
               participant_id: attach.participant_id,
               correlation_id: CallEngine.Id.generate(:turn),
               connection_id: attach.connection_id,
               content: text,
               audio_response: false,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    TestTransferConnection.send_text(command)
  end

  def consumed!(context), do: consumed!(context, System.monotonic_time(:millisecond) + 2_000)

  def rejected!(%{transport: :text}, :unauthorized) do
    assert_receive {:vxpipe_event, %CallEngine.Event.AgentTurnFailed{reason: :invalid_response}},
                   1_000
  end

  def rejected!(%{transport: :text} = context, :saturated) do
    room_id = context.plan.room_id

    assert_receive {:contract_model_rejection, ^room_id,
                    %{"status" => "rejected", "reason" => "saturated"}},
                   1_000
  end

  def rejected!(%{transport: :native}, reason) do
    assert_receive {:vxpipe_event, %CallEngine.Event.ToolCallFailed{reason: ^reason}}, 1_000
  end

  def await_closed!(context) do
    for pid <- [context.authority, context.registry, context.mcp_session] do
      monitor = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end
  end

  def close!(context) do
    assert :ok =
             CallEngine.end_call(
               context.plan.tenant_id,
               context.plan.room_id,
               context.room.incarnation_id
             )

    await_closed!(context)
  end

  def converse!(context, text \\ "HELLO") do
    assert :ok = input(context, text)
    reply = if context.transport == :text, do: "REPLY " <> text, else: "RECEIVED " <> text
    await_reply(context, reply, %{}, System.monotonic_time(:millisecond) + 55_000)
  end

  defp await_reply(context, reply, durations, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    sink = context.sink

    receive do
      {:vxpipe_event, %CallEngine.Event.TextOutput{text: ^reply}} ->
        :ok

      {:test_audio_output, ^sink, frame} ->
        duration = div(byte_size(frame.payload) * 1_000, frame.sample_rate * frame.channels * 2)
        durations = Map.update(durations, frame.correlation_id, duration, &(&1 + duration))
        await_reply(context, reply, durations, deadline)

      {:test_audio_output_finish, ^sink, turn} ->
        # Ignore an older finish invalidated by subsequent caller input. The
        # existing sink fixture reports playback against its current callback.
        if match?(%{callback: {_, ^turn}}, :sys.get_state(sink)) do
          duration = Map.fetch!(durations, turn)
          assert :ok = TestAudioOutputSink.playback_progress(sink, duration, duration)
          assert :ok = TestAudioOutputSink.playback_completed(sink)
        end

        await_reply(context, reply, Map.delete(durations, turn), deadline)
    after
      remaining -> flunk("continued conversation produced no observable reply")
    end
  end

  defp consumed!(context, deadline) do
    case CallEngine.Tool.InvocationRegistry.snapshot(context.registry) do
      {:ok, []} ->
        _ = :sys.get_state(context.authority)
        :ok

      {:ok, _pending} ->
        assert System.monotonic_time(:millisecond) < deadline, "tool outcomes were not consumed"

        receive do
        after
          5 -> consumed!(context, deadline)
        end
    end
  end

  defp compile!(store, path, mode) do
    capabilities =
      if path == :llm,
        do: %{model_inference: %{provider: "fixture", model: "test:scripted"}},
        else: %{
          speech_to_speech: %{provider: "morse", model: path, options: %{unit_duration_ms: 20}}
        }

    source = %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      tool_visibility: "full",
      call_variables: %{
        sections: %{
          "intake" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"appointment" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller find their appointment.",
          first_message: %{mode: "wait_for_input"},
          capabilities: capabilities,
          transfers: [],
          variable_permissions: %{"intake" => ["read", "write"]},
          tools: %{
            "customer_lookup" => %{
              type: "mcp",
              integration: "records",
              tool: "lookup_customer",
              conversation_mode: mode
            },
            "current_time" => %{type: "platform", tool: "get_current_time"},
            "end_call" => %{type: "platform", tool: "hangup"}
          }
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "tool-contract", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "tool-contract", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-demo",
               actor_id: "actor-contract"
             )

    assert {:ok, plan} =
             CallEngine.compile_call_spec(spec, invocation, %{host_tools: %{}},
               mcp_catalog_store: store
             )

    plan
  end

  defp model_loop(observer) do
    receive do
      {:test_agent_runtime_stream, provider, request} ->
        for %Message{role: :tool, content: content} <- request.messages do
          case JSON.decode!(content) do
            %{"status" => "rejected"} = result ->
              send(
                observer,
                {:contract_model_rejection, request.correlation.tool_context.room_id, result}
              )

            _other ->
              :ok
          end
        end

        calls =
          case List.last(request.messages) do
            %Message{role: :user, origin: :caller, content: "TOOLS " <> encoded} ->
              Enum.map(JSON.decode!(encoded), fn item ->
                {:ok, call} =
                  ToolCall.new(
                    id: Map.get(item, "id", CallEngine.Id.generate(:tool_attempt)),
                    name: Map.fetch!(item, "name"),
                    arguments: Map.fetch!(item, "arguments")
                  )

                call
              end)

            _continuation ->
              []
          end

        text =
          case {calls, List.last(request.messages)} do
            {[], %Message{role: :user, origin: :caller, content: content}} -> "REPLY " <> content
            {[], _continuation} -> "READY"
            {_calls, _message} -> ""
          end

        {:ok, response} = ModelResponse.new(text: text, tool_calls: calls)
        send(provider, {:test_agent_runtime_response, {:ok, response}})
        model_loop(observer)
    end
  end
end
