defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.OpenAIReplay do
  @moduledoc false

  alias Elixir.ReqLLM.Message.ReasoningDetails
  alias Vxpipe.AgentRuntime.{Message, ProviderReplay}

  @keys ~w(format provider model source_digest reasoning_items phase)
  @phases [nil, "commentary", "final_answer"]

  @spec capture(term(), term(), String.t(), list()) :: {:ok, map()} | {:error, atom()}
  def capture(%LLMDB.Model{provider: :openai} = model, response, text, calls) do
    id = model.id
    message = response.message
    metadata = message.metadata
    details = message.reasoning_details || []

    with false <-
           Map.has_key?(metadata, :phase_items) or Map.has_key?(metadata, :responses_replay),
         {:ok, phase} <- supported_phase(message),
         true <- Enum.all?(message.content, &(&1.type in [:text, :thinking])),
         true <- length(message.tool_calls || []) == length(calls),
         {:ok, items} <- reasoning_items(details) do
      replay =
        if items == [] and is_nil(phase) do
          %{}
        else
          %{
            "format" => "openai_responses_v1",
            "provider" => "openai",
            "model" => id,
            "wire_model" => model.provider_model_id || id,
            "source_digest" => digest(text, calls),
            "reasoning_items" => items,
            "phase" => phase
          }
        end

      with :ok <- ProviderReplay.validate(replay), do: {:ok, replay}
    else
      _invalid -> {:error, :invalid_provider_replay}
    end
  end

  def capture(_model, _response, _text, _calls), do: {:ok, %{}}

  @spec restore(Elixir.ReqLLM.Message.t(), Message.t(), LLMDB.Model.t()) ::
          Elixir.ReqLLM.Message.t()
  def restore(projected, %Message{provider_replay: replay}, _model) when replay == %{},
    do: projected

  def restore(projected, %Message{} = source, %LLMDB.Model{provider: :openai} = model) do
    id = model.id
    replay = source.provider_replay

    with true <-
           match?({:ok, :openai_responses, _, _}, Elixir.ReqLLM.RequestPlan.openai_surface(model)),
         :ok <- ProviderReplay.validate(replay),
         true <- Enum.sort(Map.keys(Map.delete(replay, "wire_model"))) == Enum.sort(@keys),
         true <- Map.get(replay, "wire_model", id) == (model.provider_model_id || id),
         %{
           "format" => "openai_responses_v1",
           "provider" => "openai",
           "model" => ^id,
           "reasoning_items" => items,
           "phase" => phase,
           "source_digest" => source_digest
         } <- replay,
         true <- source_digest == digest(source.content, source.tool_calls),
         true <- phase in @phases,
         true <- is_list(items) and Enum.all?(items, &valid_item?/1) do
      details =
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          %ReasoningDetails{
            text: nil,
            signature: item["encrypted_content"],
            encrypted?: not is_nil(item["encrypted_content"]),
            provider: :openai,
            format: "openai-responses-v1",
            index: index,
            provider_data: %{
              "id" => item["id"],
              "type" => "reasoning",
              "summary" => item["summary"]
            }
          }
        end)

      metadata = if is_nil(phase), do: %{}, else: %{phase: phase}
      %{projected | reasoning_details: details, metadata: metadata}
    else
      _invalid -> raise ArgumentError, "invalid or incompatible provider replay"
    end
  end

  def restore(_projected, _source, _model),
    do: raise(ArgumentError, "invalid or incompatible provider replay")

  defp reasoning_items(details) when is_list(details) do
    sorted = Enum.sort_by(details, & &1.index)

    if Enum.with_index(sorted)
       |> Enum.all?(fn {detail, index} -> valid_detail?(detail, index) end) do
      {:ok,
       Enum.map(sorted, fn detail ->
         %{
           "id" => detail.provider_data["id"],
           "encrypted_content" => detail.signature,
           "summary" => summary(detail)
         }
       end)}
    else
      {:error, :invalid_provider_replay}
    end
  end

  defp reasoning_items(_details), do: {:error, :invalid_provider_replay}

  defp supported_phase(message) do
    text_parts = Enum.filter(message.content, &(&1.type == :text))
    overall = Map.get(message.metadata, :phase)
    phases = Enum.map(text_parts, &(Map.get(&1.metadata, :phase) || overall)) |> Enum.uniq()

    if overall in @phases and Enum.all?(phases, &(&1 in @phases)) and
         length(phases) <= 1 and
         (is_nil(overall) or phases in [[], [overall]]) do
      {:ok, List.first(phases) || overall}
    else
      {:error, :unsupported_provider_layout}
    end
  end

  defp valid_detail?(
         %ReasoningDetails{provider: :openai, format: "openai-responses-v1", index: index} =
           detail,
         index
       ) do
    is_map(detail.provider_data) and
      Enum.all?(Map.keys(detail.provider_data), &(&1 in ["id", "type", "summary"])) and
      detail.provider_data["type"] == "reasoning" and
      detail.encrypted? == not is_nil(detail.signature) and
      valid_item?(%{
        "id" => detail.provider_data["id"],
        "encrypted_content" => detail.signature,
        "summary" => summary(detail)
      })
  end

  defp valid_detail?(_detail, _index), do: false

  defp summary(%ReasoningDetails{provider_data: %{"summary" => summary}}), do: summary

  defp summary(%ReasoningDetails{text: text}) when is_binary(text),
    do: [%{"type" => "summary_text", "text" => text}]

  defp summary(_detail), do: []

  defp valid_item?(%{"id" => id, "encrypted_content" => opaque, "summary" => summary} = item) do
    map_size(item) == 3 and is_binary(id) and id != "" and
      (is_nil(opaque) or is_binary(opaque)) and is_list(summary) and
      Enum.all?(summary, fn
        %{"type" => "summary_text", "text" => text} = part ->
          map_size(part) == 2 and is_binary(text)

        _invalid ->
          false
      end)
  end

  defp valid_item?(_item), do: false

  defp digest(text, calls) do
    canonical = {text, Enum.map(calls, &{&1.id, &1.name, &1.arguments, &1.provider_metadata})}

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical, [:deterministic]))
    |> Base.encode16(case: :lower)
  end
end
