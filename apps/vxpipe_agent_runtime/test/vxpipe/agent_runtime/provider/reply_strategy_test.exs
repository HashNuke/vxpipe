defmodule Vxpipe.AgentRuntime.Provider.ReplyStrategyTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ModelOverrides
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  test "Google native encoding needs affirmative schema evidence without gating admission" do
    {:ok, model} = ModelOverrides.resolve(:google, "gemini-3.5-flash-lite")

    for json <- [%{}, %{schema: false}, %{schema: nil}] do
      model = %{model | capabilities: Map.put(model.capabilities, :json, json)}
      assert {:ok, config} = Provider.new(api_key: "test-only", model: model)
      assert config.reply_strategy == :portable_json
      assert Provider.supports_protocol?(config, :mode_message_v1, [])
    end

    supported = %{model | capabilities: Map.put(model.capabilities, :json, %{schema: true})}
    assert {:ok, config} = Provider.new(api_key: "test-only", model: supported)
    assert config.reply_strategy == :google_object
    assert Provider.supports_protocol?(config, :mode_message_v1, [])

    # Capability evidence cannot override an SDK encoding rejection.
    older = %{supported | id: "gemini-2.5-flash", provider_model_id: "gemini-2.5-flash"}
    assert {:ok, config} = Provider.new(api_key: "test-only", model: older)
    assert config.reply_strategy == :portable_json
    assert Provider.supports_protocol?(config, :mode_message_v1, [])
  end
end
