defmodule Vxpipe.AgentRuntime.ProviderSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ProviderSelection

  @routing %{
    "fallback" => "anthropic",
    "routing" => %{
      "type" => "priority",
      "primary_factor" => "quality",
      "providers" => ["openai", "anthropic"]
    }
  }

  test "preserves the existing Zenmux model path and nested routing with a fixed endpoint" do
    assert {:ok, options} =
             ProviderSelection.translate(
               "zenmux",
               "openai/gpt-5",
               %{"temperature" => 0.2, "max_tokens" => 256},
               %{"provider" => @routing}
             )

    assert Keyword.fetch!(options, :model) == "zenmux:openai/gpt-5"
    assert Keyword.fetch!(options, :streaming)
    generation = Keyword.fetch!(options, :generation_options)
    assert Keyword.fetch!(generation, :base_url) == "https://zenmux.ai/api/v1"
    assert Keyword.fetch!(generation, :temperature) == 0.2
    assert Keyword.fetch!(generation, :max_tokens) == 256

    assert Keyword.fetch!(generation, :provider_options) == [
             provider: %{
               fallback: "anthropic",
               routing: %{
                 type: "priority",
                 primary_factor: "quality",
                 providers: ["openai", "anthropic"]
               }
             }
           ]

    refute Keyword.has_key?(options, :api_key)

    assert {:ok, _options} = ProviderSelection.translate("zenmux", "openai/gpt-5", %{}, %{})
  end

  test "rejects malformed native routing and private Zenmux options before construction" do
    for {model, common, specific} <- [
          {"zenmux:openai/gpt-5", %{}, %{}},
          {"openai/gpt-5", %{"output_repair" => fn _ -> :ok end}, %{}},
          {"openai/gpt-5", %{}, %{"api_key" => "private-marker"}},
          {"openai/gpt-5", %{}, %{"base_url" => "https://private-marker"}},
          {"openai/gpt-5", %{}, %{"req_http_options" => %{}}},
          {"openai/gpt-5", %{}, %{"provider" => "anthropic"}},
          {"openai/gpt-5", %{}, %{"provider" => %{"fallback" => 42}}},
          {"openai/gpt-5", %{}, %{"provider" => %{"api_key" => "private-marker"}}},
          {"openai/gpt-5", %{},
           %{"provider" => put_in(@routing, ["routing", "type"], "unsupported")}},
          {"openai/gpt-5", %{},
           %{"provider" => put_in(@routing, ["routing", "providers"], "openai")}},
          {"openai/gpt-5", %{},
           %{"provider" => put_in(@routing, ["routing", "providers"], ["https://private-marker"])}},
          {"openai/gpt-5", %{}, %{"provider" => put_in(@routing, ["routing", "headers"], %{})}}
        ] do
      assert {:error, :invalid_provider_selection} =
               ProviderSelection.translate("zenmux", model, common, specific)
    end

    for provider <- ["anthropic", "bedrock", "azure", "vertex"] do
      assert {:error, :invalid_provider_selection} =
               ProviderSelection.translate(provider, "model", %{}, %{})
    end
  end

  test "routes the new direct services and preserves the current DeepSeek wire model" do
    for {provider, model, req_provider} <- [
          {"deepseek", "deepseek-flash", :deepseek},
          {"openrouter", "google/gemini-3.5-flash-lite", :openrouter},
          {"fireworks", "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b", :fireworks_ai}
        ] do
      assert {:ok, options} =
               ProviderSelection.translate(provider, model, %{"max_tokens" => 256}, %{})

      assert {:ok, config} =
               Vxpipe.AgentRuntime.Provider.ReqLLM.new(
                 Keyword.put(options, :api_key, "synthetic")
               )

      assert config.model.provider == req_provider
      assert config.model.id == model
      assert config.streaming
      assert config.maximum_output_tokens == 256

      assert {:ok, defaults} = ProviderSelection.translate(provider, model, %{}, %{})

      assert {:ok, default_config} =
               Vxpipe.AgentRuntime.Provider.ReqLLM.new(
                 Keyword.put(defaults, :api_key, "synthetic")
               )

      assert default_config.maximum_output_tokens == 4096

      for private <- [
            %{"base_url" => "https://todo"},
            %{"api_key" => "synthetic"},
            %{"req_http_options" => %{}}
          ] do
        assert {:error, :invalid_provider_selection} =
                 ProviderSelection.translate(provider, model, %{}, private)
      end
    end
  end

  test "supports the bounded DeepSeek thinking control without opening transport options" do
    assert {:ok, options} =
             ProviderSelection.translate("deepseek", "deepseek-flash", %{}, %{
               "thinking" => "disabled"
             })

    generation = Keyword.fetch!(options, :generation_options)
    assert Keyword.fetch!(generation, :provider_options) == [thinking: %{type: "disabled"}]

    assert {:error, :invalid_provider_selection} =
             ProviderSelection.translate("deepseek", "deepseek-flash", %{}, %{
               "thinking" => "arbitrary"
             })
  end

  test "the current OpenAI Luna wire model uses a bounded output token limit" do
    assert {:ok, options} =
             ProviderSelection.translate("openai", "gpt-6-luna", %{"max_tokens" => 256}, %{})

    assert Keyword.fetch!(Keyword.fetch!(options, :generation_options), :max_output_tokens) ==
             256

    assert {:ok, config} =
             Vxpipe.AgentRuntime.Provider.ReqLLM.new(Keyword.put(options, :api_key, "synthetic"))

    assert config.model.id == "gpt-6-luna"
  end

  test "translates an OpenAI model using only public generation options" do
    assert {:ok, options} =
             ProviderSelection.translate("openai", "gpt-5", %{"max_tokens" => 256}, %{})

    assert Keyword.fetch!(options, :model) == "openai:gpt-5"
    assert Keyword.fetch!(options, :streaming)

    assert Keyword.fetch!(Keyword.fetch!(options, :generation_options), :max_completion_tokens) ==
             256

    refute Keyword.has_key?(options, :api_key)

    for specific <- [%{"api_key" => "private-marker"}, %{"base_url" => "https://example.com"}] do
      assert {:error, :invalid_provider_selection} =
               ProviderSelection.translate("openai", "gpt-5", %{}, specific)
    end
  end

  test "translates provider-local Google selection and pins endpoint and header authentication" do
    assert {:ok, options} =
             ProviderSelection.translate(
               "google",
               "gemini-2.5-flash",
               %{"temperature" => 0.2, "max_tokens" => 256},
               %{"google_thinking_budget" => 1024}
             )

    assert Keyword.fetch!(options, :model) == "google:gemini-2.5-flash"
    assert Keyword.fetch!(options, :streaming) == true
    generation = Keyword.fetch!(options, :generation_options)
    assert Keyword.fetch!(generation, :temperature) == 0.2

    assert Keyword.fetch!(generation, :base_url) ==
             "https://generativelanguage.googleapis.com/v1beta"

    provider = Keyword.fetch!(generation, :provider_options)
    assert Keyword.fetch!(provider, :google_auth_header)
    assert Keyword.fetch!(provider, :google_thinking_budget) == 1024
    refute Keyword.has_key?(options, :api_key)
  end

  test "rejects private transport options, unsupported providers and conflicting thinking controls" do
    for {provider, model, common, specific} <- [
          {"req_llm", "google:gemini-2.5-flash", %{}, %{}},
          {"google", "openai:gpt-5", %{}, %{}},
          {"google", "gemini-2.5-flash", %{"api_key" => "private-marker"}, %{}},
          {"google", "gemini-2.5-flash", %{"temperature" => -1}, %{}},
          {"google", "gemini-2.5-flash", %{}, %{"google_auth_header" => false}},
          {"google", "gemini-2.5-flash", %{}, %{"base_url" => "https://private-marker"}},
          {"google", "gemini-2.5-flash", %{},
           %{"google_thinking_budget" => 1024, "google_thinking_level" => "high"}}
        ] do
      assert {:error, :invalid_provider_selection} =
               ProviderSelection.translate(provider, model, common, specific)
    end
  end
end
