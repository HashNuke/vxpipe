defmodule Vxpipe.AgentRuntime.Provider.ReqLLMReplayTest do
  use ExUnit.Case, async: true

  alias Elixir.ReqLLM.{Context, Response, StreamChunk, StreamResponse}
  alias Elixir.ReqLLM.Providers.OpenAI.ResponsesAPI
  alias Vxpipe.AgentRuntime.{Message, ModelRequest}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.{Config, ResponseNormalizer}

  test "buffered and streamed native reasoning replay preserves opaque items and call order" do
    response = response()
    assert {:ok, normalized} = ResponseNormalizer.normalize(response, :mode_message_v1, model())
    assert_replay(normalized)

    {:ok, handle} =
      StreamResponse.MetadataHandle.start_link(fn -> %{finish_reason: :tool_calls} end)

    stream = %StreamResponse{
      model: model(),
      context: Context.new(),
      metadata_handle: handle,
      cancel: fn -> :ok end,
      stream: [
        StreamChunk.text("Checking."),
        StreamChunk.tool_call("lookup", %{}, %{id: "call_replay"}),
        StreamChunk.meta(%{
          reasoning_details: response.message.reasoning_details,
          finish_reason: :tool_calls
        })
      ]
    }

    assert {:ok, streamed} = Provider.consume_stream(stream, fn _ -> :ok end, :mode_message_v1)
    assert_replay(streamed)
  end

  test "replay cannot restore redacted text, removed calls, or cross model protocol data" do
    {:ok, normalized} = ResponseNormalizer.normalize(response(), :mode_message_v1, model())

    message =
      Message.assistant(normalized.text, normalized.tool_calls, normalized.provider_replay)

    for changed <- [%{message | content: "redacted"}, %{message | tool_calls: []}] do
      assert_raise ArgumentError, fn -> project([changed], model()) end
    end

    for changed_model <- [
          %{model() | id: "another-model"},
          %{model() | provider: :google},
          %{model() | provider_model_id: "another-model"},
          %{model() | extra: Map.put(model().extra, :wire, %{protocol: "openai_chat"})}
        ] do
      assert_raise ArgumentError, fn -> project([message], changed_model) end
    end

    forged = %{
      message
      | provider_replay:
          Map.put(message.provider_replay, "phase_items", [%{"text" => "old secret"}])
    }

    assert_raise ArgumentError, fn -> project([forged], model()) end
  end

  test "unsupported shadow content, multi phase, and malformed reasoning fail before admission" do
    response = response()

    for metadata <- [
          %{phase_items: [%{"phase" => "commentary", "text" => "old secret"}]},
          %{responses_replay: %{provider: :openai, items: [%{"type" => "function_call"}]}},
          %{phase: "unknown"}
        ] do
      invalid = %{response | message: %{response.message | metadata: metadata}}

      assert {:error, :invalid_provider_response} =
               ResponseNormalizer.normalize(invalid, :mode_message_v1, model())
    end

    [detail] = response.message.reasoning_details

    for invalid_detail <- [
          %{detail | provider: :google},
          %{detail | format: "unknown"},
          %{detail | signature: String.duplicate("x", 65_536)},
          %{detail | index: 5}
        ] do
      invalid = %{response | message: %{response.message | reasoning_details: [invalid_detail]}}

      assert {:error, :invalid_provider_response} =
               ResponseNormalizer.normalize(invalid, :mode_message_v1, model())
    end
  end

  test "streamed content phase survives and multiple content phases are rejected" do
    builder = Elixir.ReqLLM.Providers.OpenAI.ResponsesAPI.ResponseBuilder
    call = StreamChunk.tool_call("lookup", %{}, %{id: "call_replay"})
    commentary = StreamChunk.text("Checking.", %{phase: "commentary", output_index: 0})

    {:ok, response} =
      builder.build_response([commentary, call], %{finish_reason: :tool_calls},
        context: Context.new(),
        model: model()
      )

    {:ok, normalized} = ResponseNormalizer.normalize(response, :mode_message_v1, model())
    native = Message.assistant(normalized.text, normalized.tool_calls, normalized.provider_replay)

    [speech, _call] =
      [native] |> project(model()) |> ResponsesAPI.encode_input_items(model().id, :openai, true)

    assert speech["phase"] == "commentary"

    for later <- [StreamChunk.text("Final.", %{phase: "final_answer", output_index: 1})] do
      {:ok, mixed} =
        builder.build_response([commentary, later, call], %{finish_reason: :tool_calls},
          context: Context.new(),
          model: model()
        )

      assert {:error, :invalid_provider_response} =
               ResponseNormalizer.normalize(mixed, :mode_message_v1, model())
    end
  end

  defp assert_replay(normalized) do
    assert [call] = normalized.tool_calls
    assert call.id == "call_replay"
    refute inspect(normalized.provider_metadata) =~ "synthetic-opaque"

    retained = [
      Message.assistant(normalized.text, [call], normalized.provider_replay),
      Message.tool(call, %{"status" => "running"})
    ]

    wire =
      retained |> project(model()) |> ResponsesAPI.encode_input_items("gpt-6-luna", :openai, true)

    assert [reasoning, speech, native, result] = wire

    assert reasoning == %{
             "type" => "reasoning",
             "id" => "rs_replay",
             "encrypted_content" => "synthetic-opaque",
             "summary" => []
           }

    assert speech["content"] == [%{"type" => "output_text", "text" => "Checking."}]
    assert native["type"] == "function_call"
    assert native["call_id"] == call.id
    assert result["type"] == "function_call_output"
    assert result["call_id"] == call.id
  end

  defp project(messages, model) do
    config = %Config{
      api_key: "test-only",
      model: model,
      generation_options: [],
      streaming: true,
      context_window_tokens: nil,
      maximum_output_tokens: nil
    }

    {_model, context, _options} =
      Provider.prepare_request(config, ModelRequest.new(messages, [], [], %{}))

    context
  end

  defp model do
    {:ok, model} = Vxpipe.AgentRuntime.ModelOverrides.resolve(:openai, "gpt-6-luna")
    model
  end

  defp response do
    call = Elixir.ReqLLM.ToolCall.new("call_replay", "lookup", "{}")

    detail = %Elixir.ReqLLM.Message.ReasoningDetails{
      provider: :openai,
      format: "openai-responses-v1",
      index: 0,
      text: nil,
      signature: "synthetic-opaque",
      encrypted?: true,
      provider_data: %{"id" => "rs_replay", "type" => "reasoning"}
    }

    %Response{
      id: "response_replay",
      model: "openai:gpt-6-luna",
      context: Context.new(),
      message: %{
        Context.assistant("Checking.", tool_calls: [call])
        | reasoning_details: [detail],
          metadata: %{phase: "commentary"}
      },
      finish_reason: :tool_calls,
      usage: %{}
    }
  end
end
