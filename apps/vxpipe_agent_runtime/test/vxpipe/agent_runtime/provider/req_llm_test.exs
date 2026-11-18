defmodule Vxpipe.AgentRuntime.Provider.ReqLLMTest do
  use ExUnit.Case, async: true

  alias Elixir.ReqLLM.{Context, Response, StreamChunk, StreamResponse}

  alias Vxpipe.AgentRuntime.{
    Message,
    ModelRequest,
    ModelResponse,
    ModelTool,
    PendingInvocation,
    ToolCall
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.ResponseNormalizer

  test "acknowledges validated stateless initialization without generation" do
    assert {:ok, config} =
             Provider.new(api_key: "readiness-test-secret", model: "google:gemini-3.5-flash-lite")

    assert :ready = Provider.readiness(config)
    assert :failed = Provider.readiness(nil)
    assert :failed = Provider.readiness(%{model: "not-resolved"})
  end

  test "resolves configuration without exposing or accepting credential overrides" do
    assert {:ok, config} =
             Provider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [max_tokens: 256],
               streaming: false
             )

    refute Provider.streaming?(config)
    refute inspect(config) =~ "runtime-secret"
    assert config.context_window_tokens == 1_048_576
    assert config.maximum_output_tokens == 256
    assert config.generation_options[:on_unsupported] == :error

    assert {:error, :invalid_configuration} =
             Provider.new(model: "google:gemini-3.5-flash-lite")

    assert {:error, :invalid_configuration} =
             Provider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [api_key: "override"]
             )

    assert {:error, :invalid_configuration} =
             Provider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [provider_options: [provider: %{fallback: true}]]
             )
  end

  test "accepts and passes through routing fallback only for a supporting provider" do
    routing = %{
      fallback: "anthropic",
      routing: %{
        type: "priority",
        providers: ["openai", "anthropic"]
      }
    }

    assert {:ok, config} =
             Provider.new(
               api_key: "runtime-secret",
               model: "zenmux:openai/gpt-5",
               generation_options: [provider_options: [provider: routing]],
               streaming: false
             )

    request = ModelRequest.new([Message.system("policy"), Message.user("hello")], [], [], %{})
    {_model, _context, options} = Provider.prepare_request(config, request)

    assert get_in(options, [:provider_options, :provider]) == routing
    assert options[:on_unsupported] == :error
  end

  test "modern profiles reject object-operation overrides and permanently forced tools" do
    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")

    {:ok, contract} =
      Elixir.ReqLLM.Output.compile(
        Elixir.ReqLLM.Output.object(Vxpipe.AgentRuntime.Dialogue.schema())
      )

    tool = %ModelTool{name: "lookup", description: "Lookup", input_schema: %{"type" => "object"}}

    request = %{
      ModelRequest.new([Message.user("SHORT")], [tool], [], %{})
      | reply_protocol: :mode_message_v1
    }

    for generation_options <- [
          [operation: :object, compiled_schema: contract.compiled_schema],
          [output_repair: fn _output -> {:ok, %{}} end],
          [tool_outputs: [%{call_id: "unowned", output: "invented tool success"}]],
          [
            provider_options: [
              tool_outputs: [%{call_id: "unowned", output: "invented tool success"}]
            ]
          ],
          [previous_response_id: "unowned-history"],
          [context_management: [%{type: "compaction"}]],
          [provider_options: [context_management: [%{type: "compaction"}]]],
          [tool_choice: :required],
          [tool_choice: "required"],
          [tool_choice: %{type: "function", function: %{name: "lookup"}}]
        ] do
      assert {:ok, config} =
               Provider.new(
                 api_key: "test-only",
                 model: model,
                 generation_options: generation_options
               )

      refute Provider.supports_protocol?(config, :mode_message_v1, [tool])
      assert_raise ArgumentError, fn -> Provider.prepare_request(config, request) end
      assert {_, _, _} = Provider.prepare_request(config, %{request | reply_protocol: :legacy})
    end
  end

  test "modern selection accepts Google and alternate models while rejecting protocol overrides" do
    {:ok, google} = Provider.new(api_key: "test-only", model: "google:gemini-3.5-flash-lite")
    assert Provider.supports_protocol?(google, :mode_message_v1, [])
    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")
    {:ok, supported} = Provider.new(api_key: "test-only", model: model)
    assert Provider.supports_protocol?(supported, :mode_message_v1, [])

    for options <- [
          [provider_options: [previous_response_id: "old_response"]],
          [provider_options: [response_format: %{type: "json_object"}]]
        ] do
      {:ok, config} =
        Provider.new(api_key: "test-only", model: model, generation_options: options)

      refute Provider.supports_protocol?(config, :mode_message_v1, [])
    end

    assert Provider.supports_protocol?(
             %{supported | model: %{model | extra: %{}}},
             :mode_message_v1,
             []
           )

    for altered <- [
          %{model | provider_model_id: "unverified-model-alias"},
          %{model | extra: Map.put(model.extra, :wire, %{protocol: "openai_chat"})}
        ] do
      {:ok, config} = Provider.new(api_key: "test-only", model: altered)
      assert Provider.supports_protocol?(config, :mode_message_v1, [])
    end
  end

  test "projects native tools and business context while keeping pending control state private" do
    assert {:ok, config} =
             Provider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               streaming: false
             )

    {:ok, call} =
      ToolCall.new(
        id: "tool_call_1",
        name: "check_balance",
        arguments: %{"account_id" => "account_1"},
        provider_metadata: %{thought_signature: "opaque-signature"}
      )

    messages = [
      Message.system("Be concise."),
      Message.user("Check my balance", :caller),
      Message.assistant("I will check.", [call]),
      Message.tool(call, %{"invocation_id" => call.id, "status" => "running"}),
      Message.user("The worker later completed.", :engine)
    ]

    tool = %ModelTool{
      name: "check_balance",
      description: "Check an account balance",
      input_schema: %{
        "type" => "object",
        "properties" => %{"account_id" => %{"type" => "string"}},
        "required" => ["account_id"]
      }
    }

    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: "tool_call_2",
        tool_name: "fetch_rules",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_2"
      )

    request =
      ModelRequest.new(
        messages,
        [tool],
        [pending],
        %{
          "call_variables" => %{
            "order" => %{"revision" => 2, "value" => %{"id" => "order-17"}}
          }
        },
        %{request_id: "req_1"}
      )

    request = ModelRequest.with_maximum_output_tokens(request, 37)

    assert {model, context, options} = Provider.prepare_request(config, request)
    assert model.provider == :google
    assert model.id == "gemini-3.5-flash-lite"
    assert Keyword.fetch!(options, :api_key) == "runtime-secret"
    assert Keyword.fetch!(options, :max_tokens) == 37

    assert [%Elixir.ReqLLM.Tool{name: "check_balance"}] = Keyword.fetch!(options, :tools)

    projected = Context.to_list(context)
    assert Enum.map(projected, & &1.role) == [:system, :user, :assistant, :tool, :user]
    refute message_text(List.first(projected)) =~ "pending_tool_invocations"
    refute message_text(List.first(projected)) =~ "tool_call_2"
    assert message_text(List.first(projected)) =~ "call_variables"
    assert message_text(List.first(projected)) =~ "order-17"
    assert message_text(List.last(projected)) == "The worker later completed."

    assistant = Enum.at(projected, 2)
    assert [projected_call] = assistant.tool_calls
    assert projected_call.id == "tool_call_1"

    assert Elixir.ReqLLM.ToolCall.metadata(projected_call) == %{
             thought_signature: "opaque-signature"
           }
  end

  test "normalizes mixed ReqLLM responses with usage and safe provider metadata" do
    req_call =
      "tool_call_1"
      |> Elixir.ReqLLM.ToolCall.new("check_balance", ~s({"account_id":"account_1"}))
      |> Elixir.ReqLLM.ToolCall.put_metadata(%{thought_signature: "opaque-signature"})

    response = %Response{
      id: "response_1",
      model: "google:gemini-3.5-flash-lite",
      context: Context.new(),
      message: Context.assistant("I will check.", tool_calls: [req_call]),
      usage: %{input_tokens: 12, output_tokens: 4},
      finish_reason: :tool_calls,
      provider_meta: %{request_id: "provider_request_1", authorization: "private-secret"}
    }

    assert {:ok,
            %ModelResponse{
              text: "I will check.",
              tool_calls: [call],
              usage: %{input_tokens: 12, output_tokens: 4},
              provider_metadata: metadata
            } = normalized} = ResponseNormalizer.normalize(response)

    assert call.id == "tool_call_1"
    assert call.name == "check_balance"
    assert call.arguments == %{"account_id" => "account_1"}
    assert call.provider_metadata == %{thought_signature: "opaque-signature"}
    assert metadata.response_id == "response_1"
    assert metadata.request_id == "provider_request_1"
    assert metadata.provider_metadata.authorization == "[REDACTED]"
    refute inspect(normalized) =~ "private-secret"
  end

  test "structured profiles reject refusal and nonterminal output even if its JSON looks valid" do
    response = %Response{
      id: "reply",
      model: "google:gemini-3.5-flash-lite",
      context: Context.new(),
      message: Context.assistant(~s({"agent_mode":"speaker","message":"Hello."})),
      finish_reason: :stop
    }

    assert {:ok, _} = ResponseNormalizer.normalize(response, :mode_message_v1)

    for reason <- [:length, :content_filter, :error, :incomplete, nil] do
      assert {:error, :invalid_provider_response} =
               ResponseNormalizer.normalize(%{response | finish_reason: reason}, :mode_message_v1)
    end

    refused = %{response | provider_meta: %{refusals: ["refused"]}}

    assert {:error, :invalid_provider_response} =
             ResponseNormalizer.normalize(refused, :mode_message_v1)
  end

  test "modern replies preserve native calls regardless of names or accompanying prose" do
    text = ~s({"agent_mode":"speaker","message":"Hello."})
    artifact = Elixir.ReqLLM.ToolCall.new("native-json-tool", "structured_output", text)

    response = %Response{
      id: "reply",
      model: "google:gemini-3.5-flash-lite",
      context: Context.new(),
      message: Context.assistant(text, tool_calls: [artifact]),
      finish_reason: :tool_calls
    }

    assert {:ok, %ModelResponse{tool_calls: [%{name: "structured_output"}]}} =
             ResponseNormalizer.normalize(response, :mode_message_v1)

    assert {:ok, %ModelResponse{tool_calls: [_]}} = ResponseNormalizer.normalize(response)

    assert {:error, :invalid_provider_response} =
             ResponseNormalizer.normalize(
               %{response | finish_reason: :length},
               :mode_message_v1
             )

    native = Elixir.ReqLLM.ToolCall.new("real-tool", "lookup", "{}")
    mixed = %{response | message: Context.assistant(text, tool_calls: [native, artifact])}

    assert {:ok, %ModelResponse{tool_calls: [%{name: "lookup"}, %{name: "structured_output"}]}} =
             ResponseNormalizer.normalize(mixed, :mode_message_v1)

    mismatched = %{
      response
      | message: Context.assistant("Different prose", tool_calls: [artifact])
    }

    assert {:ok,
            %ModelResponse{text: "Different prose", tool_calls: [%{name: "structured_output"}]}} =
             ResponseNormalizer.normalize(mismatched, :mode_message_v1)
  end

  test "materializes a ReqLLM stream, emits text, and closes its handle" do
    owner = self()
    {:ok, model} = Elixir.ReqLLM.model("google:gemini-3.5-flash-lite")

    {:ok, metadata_handle} =
      StreamResponse.MetadataHandle.start_link(fn ->
        %{finish_reason: :stop, usage: %{input_tokens: 3, output_tokens: 2}}
      end)

    response = %StreamResponse{
      stream: [
        StreamChunk.text("Hel"),
        StreamChunk.text("lo"),
        StreamChunk.meta(%{
          finish_reason: "stop",
          usage: %{input_tokens: 3, output_tokens: 2}
        })
      ],
      metadata_handle: metadata_handle,
      cancel: fn -> send(owner, :req_llm_stream_closed) end,
      model: model,
      context: Context.new()
    }

    emit = fn text ->
      send(owner, {:streamed_text, text})
      :ok
    end

    assert {:ok,
            %ModelResponse{
              text: "Hello",
              usage: %{input_tokens: 3, output_tokens: 2}
            }} = Provider.consume_stream(response, emit)

    assert_receive {:streamed_text, "Hel"}
    assert_receive {:streamed_text, "lo"}
    assert_receive :req_llm_stream_closed
  end

  defp message_text(message) do
    Enum.map_join(message.content, "", & &1.text)
  end
end
