defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.ReplyStrategy do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Dialogue, Message}

  @spec select(LLMDB.Model.t(), keyword()) :: :google_object | :openai_responses | :portable_json
  def select(model, options \\ [])

  def select(%LLMDB.Model{provider: :google} = model, options) do
    provider_options = Keyword.get(options, :provider_options, [])

    # Capability metadata chooses encoding, never protocol admission. SDK request
    # preparation alone proves encodability, not affirmative schema support.
    # ReqLLM's object encoder also omits builtins; chat retains them with tools.
    if not Elixir.ReqLLM.ModelHelpers.json_schema?(model) or
         Enum.any?(
           [:google_grounding, :google_url_context],
           fn key -> Keyword.has_key?(provider_options, key) or Keyword.has_key?(options, key) end
         ) do
      :portable_json
    else
      google_strategy(model)
    end
  end

  def select(model, _options) do
    case Elixir.ReqLLM.RequestPlan.openai_surface(model) do
      {:ok, :openai_responses, _module, _warnings} -> :openai_responses
      _other -> :portable_json
    end
  end

  defp google_strategy(model) do
    {:ok, contract} = Elixir.ReqLLM.Output.compile(google_output())

    tool =
      Elixir.ReqLLM.Tool.new!(
        name: "dialogue_capability_probe",
        description: "Offline request preparation probe",
        parameter_schema: %{"type" => "object", "properties" => %{}},
        callback: fn _ -> {:error, :offline_probe} end
      )

    case Elixir.ReqLLM.Providers.Google.prepare_request(:object, model, "probe",
           api_key: "offline-probe",
           tools: [tool],
           compiled_schema: contract.compiled_schema
         ) do
      {:ok, _request} -> :google_object
      {:error, _unsupported} -> :portable_json
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
      :google_object ->
        Keyword.put(options, :output, google_output())

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

  defp google_output, do: Elixir.ReqLLM.Output.object(Dialogue.schema())
end
