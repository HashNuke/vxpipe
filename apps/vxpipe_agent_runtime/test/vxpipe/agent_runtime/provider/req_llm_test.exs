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

  test "resolves configuration without exposing or accepting credential overrides" do
    assert {:ok, config} =
             Provider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [temperature: 0.2],
               streaming: false
             )

    refute Provider.streaming?(config)
    refute inspect(config) =~ "runtime-secret"

    assert {:error, :invalid_configuration} =
             Provider.new(model: "google:gemini-3.5-flash-lite")

    assert {:error, :invalid_configuration} =
             Provider.new(
               api_key: "runtime-secret",
               model: "google:gemini-3.5-flash-lite",
               generation_options: [api_key: "override"]
             )
  end

  test "projects messages, exact tools, and pending state without private bindings" do
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

    assert {model, context, options} = Provider.prepare_request(config, request)
    assert model.provider == :google
    assert model.id == "gemini-3.5-flash-lite"
    assert Keyword.fetch!(options, :api_key) == "runtime-secret"

    assert [%Elixir.ReqLLM.Tool{name: "check_balance"}] = Keyword.fetch!(options, :tools)

    projected = Context.to_list(context)
    assert Enum.map(projected, & &1.role) == [:system, :user, :assistant, :tool, :user]
    assert message_text(List.first(projected)) =~ "pending_tool_invocations"
    assert message_text(List.first(projected)) =~ "tool_call_2"
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
