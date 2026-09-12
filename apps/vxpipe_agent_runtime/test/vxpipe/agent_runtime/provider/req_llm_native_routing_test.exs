defmodule Vxpipe.AgentRuntime.Provider.ReqLLMNativeRoutingTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelResponse, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @routing %{
    fallback: "anthropic",
    routing: %{
      type: "priority",
      primary_factor: "quality",
      providers: ["openai", "anthropic"]
    }
  }

  setup context do
    :ok = Req.Test.set_req_test_to_shared(context)
    Req.Test.verify_on_exit!()
  end

  test "sends one provider-native fallback request with the exact model-visible tools" do
    owner = self()

    Req.Test.expect(__MODULE__, fn connection ->
      body = connection |> Req.Test.raw_body() |> JSON.decode!()

      send(
        owner,
        {:native_routing_wire_request, connection.method, connection.request_path, body}
      )

      Req.Test.json(connection, %{
        id: "response-native-routing-1",
        object: "chat.completion",
        created: 1_789_000_000,
        model: "anthropic/claude-sonnet-4-5",
        choices: [
          %{
            index: 0,
            message: %{role: "assistant", content: "The routed provider answered."},
            finish_reason: "stop"
          }
        ],
        usage: %{prompt_tokens: 12, completion_tokens: 5, total_tokens: 17}
      })
    end)

    assert {:ok, config} =
             Provider.new(
               api_key: "controlled-secret",
               model: "zenmux:openai/gpt-5",
               generation_options: [
                 provider_options: [provider: @routing],
                 req_http_options: [plug: {Req.Test, __MODULE__}],
                 total_timeout: :infinity
               ],
               streaming: false
             )

    tool = %ModelTool{
      name: "lookup_policy",
      description: "Look up one policy.",
      input_schema: %{
        "type" => "object",
        "properties" => %{"policy_id" => %{"type" => "string"}},
        "required" => ["policy_id"],
        "additionalProperties" => false
      }
    }

    request =
      ModelRequest.new(
        [Message.system("Use only the supplied tools."), Message.user("Look up policy 17.")],
        [tool],
        [],
        %{},
        %{request_id: "native-routing-1", executor_binding: "private-executor-binding"}
      )

    result = Provider.generate(config, request)

    assert_receive {:native_routing_wire_request, "POST", "/api/v1/chat/completions", body}
    assert body["model"] == "openai/gpt-5"
    assert body["provider"] == JSON.decode!(JSON.encode!(@routing))

    assert [
             %{
               "type" => "function",
               "function" => %{
                 "name" => "lookup_policy",
                 "parameters" => %{
                   "type" => "object",
                   "properties" => %{
                     "policy_id" => %{"type" => "string"}
                   },
                   "required" => ["policy_id"],
                   "additionalProperties" => false
                 }
               }
             }
           ] = body["tools"]

    refute inspect(body) =~ "private-executor-binding"

    assert {:ok,
            %ModelResponse{
              text: "The routed provider answered.",
              tool_calls: [],
              usage: usage,
              provider_metadata: provider_metadata
            }} = result

    assert usage[:input_tokens] == 12
    assert usage[:output_tokens] == 5
    assert usage[:total_tokens] == 17
    assert provider_metadata[:model] == "anthropic/claude-sonnet-4-5"
  end
end
