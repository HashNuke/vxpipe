defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.DialogueProfile do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Provider.ReqLLM.Config

  @spec supports_model?(String.t(), String.t(), [String.t()]) :: boolean()
  def supports_model?("openai", "gpt-6-luna", names) when is_list(names),
    do: "structured_output" not in names

  def supports_model?(_provider, _model, _names), do: false

  @spec compatible_model?(term()) :: boolean()
  def compatible_model?(%LLMDB.Model{provider: :openai, id: "gpt-6-luna"} = model) do
    (model.provider_model_id || model.id) == "gpt-6-luna" and
      match?(
        {:ok, :openai_responses, _module, _warnings},
        Elixir.ReqLLM.RequestPlan.openai_surface(model)
      )
  end

  def compatible_model?(_model), do: false

  @spec supports?(term(), atom(), list()) :: boolean()
  def supports?(%Config{} = config, :mode_message_v1, tools) when is_list(tools) do
    compatible_model?(config.model) and
      supports_model?("openai", config.model.id, Enum.map(tools, & &1.name)) and
      compatible_options?(config.generation_options)
  end

  def supports?(_config, _protocol, _tools), do: false

  defp compatible_options?(options) do
    Enum.all?(
      [:operation, :compiled_schema, :output, :output_repair, :response_format],
      &(not Keyword.has_key?(options, &1))
    ) and Keyword.get(options, :tool_choice) in [nil, :auto, "auto"] and
      Keyword.get(options, :provider_options, []) == []
  end
end
