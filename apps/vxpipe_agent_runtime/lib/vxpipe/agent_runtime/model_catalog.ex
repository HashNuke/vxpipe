defmodule Vxpipe.AgentRuntime.ModelCatalog do
  @moduledoc "Locally runnable tool-calling text models from LLMDB and runtime overrides."

  alias Vxpipe.AgentRuntime.{ModelOverrides, ProviderSelection}

  @providers %{
    "google" => {:google, "gemini-2.5-flash"},
    "openai" => {:openai, "gpt-5"},
    "zenmux" => {:zenmux, "openai/gpt-5"},
    "deepseek" => {:deepseek, "deepseek-flash"},
    "openrouter" => {:openrouter, "google/gemini-3.5-flash-lite"},
    "fireworks" => {:fireworks_ai, "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"}
  }

  def models(provider) do
    case Map.fetch(@providers, provider) do
      {:ok, {native, default}} -> {:ok, list(provider, native, default)}
      :error -> {:error, :unsupported_provider}
    end
  end

  defp list(provider, native, default) do
    (LLMDB.models(native) ++ ModelOverrides.models(native))
    |> Map.new(&{&1.id, &1})
    |> Map.values()
    |> Enum.filter(&chat_model?/1)
    |> Enum.filter(
      &match?({:ok, _options}, ProviderSelection.translate(provider, &1.id, %{}, %{}))
    )
    |> Enum.map(fn model ->
      %{
        id: model.id,
        name: model.name || model.id,
        default: model.id == default,
        voices: nil,
        tool_support: true,
        context_limit: Map.get(model.limits || %{}, :context)
      }
    end)
    |> Enum.sort_by(&{not &1.default, &1.name, &1.id})
  end

  defp chat_model?(model) do
    output = Map.get(model.modalities || %{}, :output) || []

    :text in output and :image not in output and :video not in output and
      get_in(model.capabilities || %{}, [:tools, :enabled]) == true
  end
end
