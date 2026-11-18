defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.GoogleReplay do
  @moduledoc false

  alias Elixir.ReqLLM.Message.ReasoningDetails
  alias Vxpipe.AgentRuntime.ProviderReplay
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.GoogleParts

  @keys ~w(format provider model wire_model source_digest parts)

  def capture(model, response, text, calls) do
    with true <- Enum.all?(response.message.content, &(&1.type in [:text, :thinking])),
         {:ok, parts} <- capture_parts(response.message.reasoning_details || [], text, calls) do
      replay =
        if parts == [] and calls == [] do
          %{}
        else
          %{
            "format" => "google_generate_content_v1",
            "provider" => "google",
            "model" => model.id,
            "wire_model" => model.provider_model_id || model.id,
            "source_digest" => digest(text, calls),
            "parts" => parts
          }
        end

      with :ok <- validate_bound(replay, calls), do: {:ok, replay}
    else
      _invalid -> {:error, :invalid_provider_replay}
    end
  end

  def restore(projected, source, %LLMDB.Model{provider: :google} = model) do
    replay = source.provider_replay

    with :ok <- validate_bound(replay, source.tool_calls),
         true <- Enum.sort(Map.keys(replay)) == Enum.sort(@keys),
         true <- replay["provider"] == "google",
         true <- replay["model"] == model.id,
         true <- replay["wire_model"] == (model.provider_model_id || model.id),
         true <- replay["source_digest"] == digest(source.content, source.tool_calls),
         {:ok, parts} <- GoogleParts.restore(replay["parts"], source.content, source.tool_calls) do
      details =
        parts
        |> Enum.with_index()
        |> Enum.map(fn {part, index} ->
          %ReasoningDetails{
            provider: :google,
            format: "google-generate-content-parts-v1",
            index: index,
            text: nil,
            signature: nil,
            encrypted?: false,
            provider_data: %{"part" => part}
          }
        end)

      %{projected | reasoning_details: details}
    else
      _invalid -> raise ArgumentError, "invalid or incompatible provider replay"
    end
  end

  def restore(_projected, _source, _model),
    do: raise(ArgumentError, "invalid or incompatible provider replay")

  defp capture_parts([], _text, []), do: {:ok, []}
  defp capture_parts(details, text, calls), do: GoogleParts.capture(details, text, calls)

  defp validate_bound(replay, calls) do
    signatures =
      Enum.map(calls, fn call ->
        Enum.reduce(call.provider_metadata, %{}, fn
          {key, value}, acc
          when key in [:thought_signature, "thought_signature", :google_call_id, "google_call_id"] and
                 is_binary(value) ->
            key = to_string(key)

            if Map.has_key?(acc, key),
              do: throw(:invalid_google_tool_metadata),
              else: Map.put(acc, key, value)

          _entry, _acc ->
            throw(:invalid_google_tool_metadata)
        end)
      end)

    ProviderReplay.validate(Map.put(replay, "tool_signatures", signatures))
  catch
    :invalid_google_tool_metadata -> {:error, :invalid_provider_replay}
  end

  defp digest(text, calls) do
    canonical = {text, Enum.map(calls, &{&1.id, &1.name, &1.arguments, &1.provider_metadata})}

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical, [:deterministic]))
    |> Base.encode16(case: :lower)
  end
end
