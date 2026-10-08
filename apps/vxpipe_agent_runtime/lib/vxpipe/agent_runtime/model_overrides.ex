defmodule Vxpipe.AgentRuntime.ModelOverrides do
  @moduledoc "Runtime model declarations newer than the bundled LLMDB snapshot."

  @overrides %{
    deepseek: [
      %{
        provider: :deepseek,
        id: "deepseek-flash",
        name: "DeepSeek V4.1 Flash",
        limits: %{context: 1_048_576, output: 393_216},
        modalities: %{input: [:text], output: [:text]},
        capabilities: %{
          tools: %{enabled: true, streaming: true},
          streaming: %{text: true, tool_calls: true}
        }
      }
    ],
    openai: [
      %{
        provider: :openai,
        id: "gpt-6-luna",
        name: "GPT-6 Luna",
        modalities: %{input: [:text], output: [:text]},
        capabilities: %{tools: %{enabled: true}},
        extra: %{
          "constraints" => %{"token_limit_key" => "max_output_tokens"},
          "wire" => %{"protocol" => "openai_responses"}
        }
      }
    ]
  }

  def models(provider) do
    Enum.map(Map.get(@overrides, provider, []), fn spec ->
      {:ok, model} = ReqLLM.model(spec)
      model
    end)
  end

  def resolve(provider, id) do
    case Enum.find(Map.get(@overrides, provider, []), &(&1.id == id)) do
      nil -> ReqLLM.model(Atom.to_string(provider) <> ":" <> id)
      spec -> ReqLLM.model(spec)
    end
  end
end
