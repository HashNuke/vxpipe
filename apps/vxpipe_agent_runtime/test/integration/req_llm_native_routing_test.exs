defmodule Vxpipe.AgentRuntime.Integration.ReqLLMNativeRoutingTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelResponse, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @moduletag :integration

  @routing %{
    fallback: "anthropic",
    routing: %{
      type: "priority",
      primary_factor: "quality",
      providers: ["openai", "anthropic"]
    }
  }

  test "Zenmux accepts native routing with an exact tool schema and reports its model" do
    assert {:ok, config} =
             Provider.new(
               api_key: System.fetch_env!("ZENMUX_API_KEY"),
               model: System.get_env("VXPIPE_ZENMUX_MODEL", "zenmux:openai/gpt-4o"),
               generation_options: [
                 provider_options: [provider: @routing],
                 tool_choice: :none,
                 max_tokens: 64,
                 total_timeout: 60_000
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
        [
          Message.system("Reply with exactly READY without calling a tool."),
          Message.user("Confirm that you are ready.")
        ],
        [tool],
        [],
        %{},
        %{request_id: "zenmux-native-routing-integration"}
      )

    assert {:ok,
            %ModelResponse{
              text: text,
              tool_calls: [],
              usage: usage,
              provider_metadata: provider_metadata
            }} = Provider.generate(config, request)

    assert String.trim(text) != ""
    assert map_size(usage) > 0
    assert is_binary(provider_metadata[:model])
    assert String.trim(provider_metadata[:model]) != ""
  end
end
