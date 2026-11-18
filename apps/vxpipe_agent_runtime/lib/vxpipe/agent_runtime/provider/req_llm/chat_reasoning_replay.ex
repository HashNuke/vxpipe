defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.ChatReasoningReplay do
  @moduledoc false

  alias Elixir.ReqLLM.Message.ContentPart
  alias Elixir.ReqLLM.Message.ReasoningDetails
  alias Vxpipe.AgentRuntime.{Message, ProviderReplay}

  @keys ~w(format provider model wire_model source_digest reasoning)

  def capture(model, response, text, calls) do
    message = response.message

    with true <- Enum.all?(message.content, &valid_part?/1) do
      reasoning =
        message.content
        |> Enum.filter(&(&1.type == :thinking))
        |> Enum.map_join("", & &1.text)

      replay =
        if reasoning == "" do
          %{}
        else
          %{
            "format" => "chat_reasoning_v1",
            "provider" => Atom.to_string(model.provider),
            "model" => model.id,
            "wire_model" => model.provider_model_id || model.id,
            "source_digest" => digest(text, calls),
            "reasoning" => reasoning
          }
        end

      with true <- equivalent_details?(message.reasoning_details, model.provider, reasoning),
           :ok <- ProviderReplay.validate(replay) do
        {:ok, replay}
      else
        _invalid -> {:error, :invalid_provider_replay}
      end
    else
      _invalid -> {:error, :invalid_provider_replay}
    end
  end

  def restore(projected, %Message{} = source, model) do
    replay = source.provider_replay

    with true <- model.provider in [:deepseek, :fireworks_ai],
         :ok <- ProviderReplay.validate(replay),
         true <- Enum.sort(Map.keys(replay)) == Enum.sort(@keys),
         true <- replay["format"] == "chat_reasoning_v1",
         true <- replay["provider"] == Atom.to_string(model.provider),
         true <- replay["model"] == model.id,
         true <- replay["wire_model"] == (model.provider_model_id || model.id),
         true <- replay["source_digest"] == digest(source.content, source.tool_calls),
         reasoning when is_binary(reasoning) and reasoning != "" <- replay["reasoning"] do
      %{projected | content: [ContentPart.thinking(reasoning) | projected.content]}
    else
      _invalid -> raise ArgumentError, "invalid or incompatible provider replay"
    end
  end

  def settlement_candidate(response, %{provider: provider} = model)
      when provider in [:deepseek, :fireworks_ai] do
    source = Message.assistant(response.text, [], response.provider_replay)

    if response.tool_calls == [] and response.provider_replay != %{} do
      _validated = restore(Elixir.ReqLLM.Context.assistant(response.text), source, model)
      {:ok, response.provider_replay}
    else
      :none
    end
  rescue
    _invalid -> :none
  end

  def settlement_candidate(_response, _model), do: :none

  def bind_settled(replay, %Message{} = message) do
    %{message | provider_replay: Map.put(replay, "source_digest", digest(message.content, []))}
  end

  defp valid_part?(%ContentPart{type: type, text: text, metadata: metadata})
       when type in [:text, :thinking],
       do: is_binary(text) and metadata == %{}

  defp valid_part?(_part), do: false

  defp equivalent_details?(details, _provider, _reasoning) when details in [nil, []], do: true

  defp equivalent_details?(details, provider, reasoning) when is_list(details) do
    valid? =
      details
      |> Enum.with_index()
      |> Enum.all?(fn
        {%ReasoningDetails{
           provider: ^provider,
           format: "openai-reasoning-content-v1",
           index: index,
           text: text,
           signature: nil,
           provider_data: nil,
           encrypted?: false
         }, index} ->
          is_binary(text)

        _invalid ->
          false
      end)

    valid? and Enum.map_join(details, "", & &1.text) == reasoning
  end

  defp equivalent_details?(_details, _provider, _reasoning), do: false

  defp digest(text, calls) do
    canonical = {text, Enum.map(calls, &{&1.id, &1.name, &1.arguments, &1.provider_metadata})}

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical, [:deterministic]))
    |> Base.encode16(case: :lower)
  end
end
