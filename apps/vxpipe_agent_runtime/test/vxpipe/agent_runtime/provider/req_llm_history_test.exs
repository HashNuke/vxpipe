defmodule Vxpipe.AgentRuntime.Provider.ReqLLMHistoryTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{
    Input,
    Message,
    ModelRequest,
    ModelTool,
    PendingInvocation,
    ToolCall
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  setup context do
    :ok = Req.Test.set_req_test_to_shared(context)
    Req.Test.verify_on_exit!()
    :ok
  end

  test "pending state adds no prompt even without an authored system message" do
    {:ok, config} = Provider.new(api_key: "test-only", model: "google:gemini-3.5-flash-lite")

    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: "tool-1",
        tool_name: "lookup",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn-1"
      )

    for messages <- [
          [Message.user("Hello")],
          [Message.system("Be concise."), Message.user("Hello")]
        ],
        business_context <- [%{}, %{"call_variables" => %{"order" => %{"id" => "17"}}}] do
      base = ModelRequest.new(messages, [], [], business_context, %{})
      {_model, baseline, _options} = Provider.prepare_request(config, base)

      for status <- [:running, :terminal_queued, :completion_admitted] do
        changed = %{base | pending_invocations: [%{pending | status: status}]}
        {_model, projected, _options} = Provider.prepare_request(config, changed)
        assert Elixir.ReqLLM.Context.to_list(projected) == Elixir.ReqLLM.Context.to_list(baseline)
      end
    end
  end

  test "structured dialogue uses one native strict schema with or without native tools" do
    owner = self()
    text = ~s({"agent_mode":"speaker","message":"Hello."})

    Req.Test.expect(__MODULE__, 2, fn connection ->
      body = connection |> Req.Test.raw_body() |> JSON.decode!()
      send(owner, {:structured_wire, body})

      Req.Test.json(connection, %{
        id: "response_profile",
        model: "gpt-6-luna",
        status: "completed",
        output: [
          %{
            type: "message",
            id: "message_profile",
            role: "assistant",
            status: "completed",
            content: [%{type: "output_text", text: text}]
          }
        ]
      })
    end)

    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: model,
        streaming: false,
        generation_options: [req_http_options: [plug: {Req.Test, __MODULE__}]]
      )

    tool = %ModelTool{
      name: "lookup",
      description: "Lookup",
      input_schema: %{"type" => "object", "properties" => %{}}
    }

    for tools <- [[], [tool]] do
      request = %{
        ModelRequest.new([Message.user("Hello")], tools, [], %{})
        | reply_protocol: :mode_message_v1
      }

      assert Provider.supports_protocol?(config, :mode_message_v1, tools)
      assert {:ok, %{text: ^text}} = Provider.generate(config, request)
      assert_receive {:structured_wire, body}
      assert get_in(body, ["text", "format", "type"]) == "json_schema"
      assert get_in(body, ["text", "format", "strict"]) == true
      assert get_in(body, ["text", "format", "schema"]) == Vxpipe.AgentRuntime.Dialogue.schema()

      if tools != [],
        do: assert([%{"type" => "function", "name" => "lookup"}] = body["tools"])
    end
  end

  test "portable Google dialogue runs through Session with real encoded HTTP and host settlement" do
    alias Vxpipe.AgentRuntime.{Event, Session}
    owner = self()
    text = ~s({"agent_mode":"speaker","message":"Hello."})

    Req.Test.expect(__MODULE__, fn connection ->
      send(owner, {:portable_wire, connection |> Req.Test.raw_body() |> JSON.decode!()})

      Req.Test.json(connection, %{
        candidates: [%{content: %{role: "model", parts: [%{text: text}]}, finishReason: "STOP"}]
      })
    end)

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: "google:gemini-3.5-flash-lite",
        streaming: false,
        generation_options: [req_http_options: [plug: {Req.Test, __MODULE__}]]
      )

    session =
      start_supervised!(
        {Session,
         [
           instructions: "Be concise",
           history_mode: :host_settled,
           reply_protocol: :mode_message_v1,
           model_provider: Provider,
           model: config,
           pending_context_source:
             {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
           event_destination: self()
         ]}
      )

    assert {:ok,
            %{
              status: :completed,
              output: nil,
              dialogue: %{agent_mode: :speaker, message: "Hello."}
            }} =
             Session.request(session, "Hello", %{request_id: "portable"})

    assert_receive {:portable_wire, body}
    assert JSON.encode!(body["systemInstruction"]) =~ "agent_mode"
    refute Map.has_key?(body, "response_format")
    refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
    assert :ok = Session.settle_output(session, %{request_id: "portable"}, nil)
  end

  test "structured output is an ordinary native tool name without synthetic schema tools" do
    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")
    {:ok, config} = Provider.new(api_key: "test-only", model: model)

    tool = %ModelTool{
      name: "structured_output",
      description: "Application tool",
      input_schema: %{"type" => "object"}
    }

    assert Provider.supports_protocol?(config, :mode_message_v1, [tool])

    request = %{
      ModelRequest.new([Message.user("hello")], [tool], [], %{})
      | reply_protocol: :mode_message_v1
    }

    assert {_, _, options} = Provider.prepare_request(config, request)
    assert [%{name: "structured_output"}] = options[:tools]
    assert {_, _, _} = Provider.prepare_request(config, %{request | reply_protocol: :legacy})
  end

  test "legacy Google preserves serialized content-part prefixes of structured history" do
    owner = self()

    Req.Test.expect(__MODULE__, 4, fn connection ->
      send(owner, {:structured_prefix_wire, connection |> Req.Test.raw_body() |> JSON.decode!()})

      Req.Test.json(connection, %{
        candidates: [
          %{
            content: %{
              role: "model",
              parts: [%{text: ~s({"agent_mode":"listener","message":null})}]
            },
            finishReason: "STOP"
          }
        ]
      })
    end)

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: "google:gemini-3.5-flash-lite",
        streaming: false,
        generation_options: [req_http_options: [plug: {Req.Test, __MODULE__}]]
      )

    {:ok, first_input} = Input.participant("human-1", "QUIET \"quoted\"\n世界", :listener)
    {:ok, next_input} = Input.participant("human-2", "SHORT", :listener)

    {:ok, call} =
      ToolCall.new(
        id: "prefix-native",
        name: "lookup",
        arguments: %{"id" => "17"},
        provider_metadata: %{thought_signature: "unchanged-native-signature"}
      )

    tool = %ModelTool{
      name: "lookup",
      description: "Lookup",
      input_schema: %{"type" => "object", "properties" => %{}}
    }

    initial = [Message.system("Fixed instructions"), Message.user(Input.encode(first_input))]
    after_silence = initial ++ [Message.user(Input.encode(next_input))]

    native =
      after_silence ++
        [
          Message.assistant("Native accompanying text", [call]),
          Message.tool(call, %{"invocation_id" => call.id, "status" => "running"})
        ]

    completed = native ++ [Message.user("Actual worker outcome: 17", :engine)]

    bodies =
      for messages <- [initial, after_silence, native, completed] do
        request = ModelRequest.new(messages, [tool], [], %{})

        assert {:ok, _response} = Provider.generate(config, request)
        assert_receive {:structured_prefix_wire, body}
        body
      end

    for [before, after_append] <- Enum.chunk_every(bodies, 2, 1, :discard) do
      assert Map.delete(before, "contents") == Map.delete(after_append, "contents")
      assert_content_part_prefix(before["contents"], after_append["contents"])
    end

    [first, silent, native_body, final] = bodies
    assert [%{"role" => "user", "parts" => [%{"text" => first_text}]}] = first["contents"]
    assert first_text == Input.encode(first_input)
    assert [%{"role" => "user", "parts" => [_first, %{"text" => next_text}]}] = silent["contents"]
    assert next_text == Input.encode(next_input)
    assert JSON.encode!(native_body) =~ "unchanged-native-signature"
    assert JSON.encode!(final) =~ "functionResponse"
    refute JSON.encode!(final) =~ "pending_tool_invocations"
    refute Enum.any?(silent["contents"], &(&1["role"] == "model"))
  end

  defp assert_content_part_prefix(before, after_append) do
    {earlier, [last]} = Enum.split(before, length(before) - 1)
    assert Enum.take(after_append, length(earlier)) == earlier
    corresponding = Enum.at(after_append, length(earlier))
    assert Map.delete(corresponding, "parts") == Map.delete(last, "parts")
    assert Enum.take(corresponding["parts"], length(last["parts"])) == last["parts"]

    assert Enum.map(Enum.take(corresponding["parts"], length(last["parts"])), &JSON.encode!/1) ==
             Enum.map(last["parts"], &JSON.encode!/1)
  end

  test "native tool history keeps its serialized prefix as pending control state changes" do
    owner = self()

    Req.Test.expect(__MODULE__, 3, fn connection ->
      body = connection |> Req.Test.raw_body() |> JSON.decode!()
      send(owner, {:wire, body})

      Req.Test.json(connection, %{
        candidates: [
          %{content: %{role: "model", parts: [%{text: "Okay."}]}, finishReason: "STOP"}
        ],
        usageMetadata: %{promptTokenCount: 12, candidatesTokenCount: 3, totalTokenCount: 15}
      })
    end)

    {:ok, config} =
      Provider.new(
        api_key: "test-only",
        model: "google:gemini-3.5-flash-lite",
        streaming: false,
        generation_options: [req_http_options: [plug: {Req.Test, __MODULE__}]]
      )

    {:ok, call} =
      ToolCall.new(
        id: "native-1",
        name: "lookup",
        arguments: %{"id" => "17"},
        provider_metadata: %{thought_signature: "opaque-signature"}
      )

    messages = [
      Message.system("Be concise."),
      Message.user("Look up 17."),
      Message.assistant("Checking.", [call]),
      Message.tool(call, %{"status" => "running", "invocation_id" => call.id})
    ]

    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: call.id,
        tool_name: call.name,
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn-1"
      )

    assert {:ok, _} = Provider.generate(config, ModelRequest.new(messages, [], [], %{}))
    assert_receive {:wire, baseline}
    assert {:ok, _} = Provider.generate(config, ModelRequest.new(messages, [], [pending], %{}))
    assert_receive {:wire, running}

    extended =
      messages ++ [Message.assistant("Working on it.", []), Message.user("What is two plus two?")]

    assert {:ok, _} = Provider.generate(config, ModelRequest.new(extended, [], [], %{}))
    assert_receive {:wire, appended}
    assert running["systemInstruction"] == baseline["systemInstruction"]
    assert running["contents"] == baseline["contents"]
    assert Enum.take(appended["contents"], length(baseline["contents"])) == baseline["contents"]
    assert JSON.encode!(baseline["contents"]) =~ "opaque-signature"
    refute JSON.encode!(running) =~ "pending_tool_invocations"
  end
end
