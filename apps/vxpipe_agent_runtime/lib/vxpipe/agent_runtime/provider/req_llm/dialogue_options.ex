defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.DialogueOptions do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Provider.ReqLLM.Config

  @spec supports?(term(), atom(), list()) :: boolean()
  def supports?(%Config{} = config, :mode_message_v1, tools) when is_list(tools) do
    compatible_options?(config.generation_options)
  end

  def supports?(_config, _protocol, _tools), do: false

  defp compatible_options?(options) do
    owned = [
      :operation,
      :compiled_schema,
      :output,
      :output_repair,
      :response_format,
      :previous_response_id,
      :conversation,
      :context_management,
      :tool_outputs
    ]

    absent?(options, owned) and
      Keyword.get(options, :tool_choice) in [nil, :auto, "auto"] and
      Keyword.get(options, :json_repair, false) == false and
      absent?(Keyword.get(options, :provider_options, []), owned)
  end

  defp absent?(options, keys), do: Enum.all?(keys, &(not Keyword.has_key?(options, &1)))
end
