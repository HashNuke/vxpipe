defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.ReplyStrategy do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Dialogue, Message}

  @spec select(LLMDB.Model.t()) :: :openai_responses | :portable_json
  def select(model) do
    case Elixir.ReqLLM.RequestPlan.openai_surface(model) do
      {:ok, :openai_responses, _module, _warnings} -> :openai_responses
      _other -> :portable_json
    end
  end

  def instruct(messages, :legacy), do: messages

  def instruct(messages, :mode_message_v1) do
    instructions = Dialogue.instructions()

    case messages do
      [%Message{role: :system} = system | rest] ->
        [%{system | content: system.content <> "\n\n" <> instructions} | rest]

      _other ->
        [Message.system(instructions) | messages]
    end
  end

  def options(options, :legacy, _strategy), do: options

  def options(options, :mode_message_v1, strategy) do
    options =
      options
      |> Keyword.put(:output, Elixir.ReqLLM.Output.text())
      |> Keyword.put(:json_repair, false)

    case strategy do
      :portable_json ->
        options

      :openai_responses ->
        format = %{
          type: "json_schema",
          json_schema: %{name: "agent_dialogue", strict: true, schema: Dialogue.schema()}
        }

        Keyword.update(
          options,
          :provider_options,
          [response_format: format],
          &Keyword.put(&1, :response_format, format)
        )
    end
  end
end
