defmodule Vxpipe.AgentRuntime.ModelCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelCatalog, ProviderSelection}

  @defaults %{
    "google" => "gemini-2.5-flash",
    "openai" => "gpt-5",
    "zenmux" => "openai/gpt-5",
    "deepseek" => "deepseek-flash",
    "openrouter" => "google/gemini-3.5-flash-lite",
    "fireworks" => "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"
  }

  for {provider, default} <- @defaults do
    test "#{provider} lists runnable tool-capable models and its recommended default" do
      assert {:ok, models} = ModelCatalog.models(unquote(provider))
      assert models != []
      assert Enum.uniq_by(models, & &1.id) == models
      assert [%{id: unquote(default)}] = Enum.filter(models, & &1.default)

      for model <- models do
        assert is_binary(model.name) and model.name != ""
        assert model.tool_support
        assert is_nil(model.context_limit) or model.context_limit > 0

        assert {:ok, _options} =
                 ProviderSelection.translate(unquote(provider), model.id, %{}, %{})
      end
    end
  end

  test "runtime overrides appear alongside snapshot models" do
    assert {:ok, deepseek} = ModelCatalog.models("deepseek")

    assert %{name: "DeepSeek V4.1 Flash", context_limit: 1_048_576} =
             Enum.find(deepseek, &(&1.id == "deepseek-flash"))

    assert {:ok, openai} = ModelCatalog.models("openai")
    assert Enum.any?(openai, &(&1.id == "gpt-6-luna"))
  end

  test "image, audio-only and models without tool support are not offered" do
    assert {:ok, models} = ModelCatalog.models("openai")
    ids = Enum.map(models, & &1.id)
    refute "dall-e-3" in ids
    refute "gpt-image-1" in ids
    refute "whisper-1" in ids

    for model <- LLMDB.models(:openai), model.id in ids do
      assert :text in model.modalities.output
      refute :image in model.modalities.output
      refute :video in model.modalities.output
      assert model.capabilities.tools.enabled
    end
  end

  test "unknown providers are rejected without expanding the supported runtime surface" do
    for provider <- ["unknown", "anthropic", "fireworks_ai", :openai, nil] do
      assert {:error, :unsupported_provider} = ModelCatalog.models(provider)
    end
  end
end
