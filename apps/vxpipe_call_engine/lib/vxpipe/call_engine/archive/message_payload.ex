defmodule Vxpipe.CallEngine.Archive.MessagePayload do
  @moduledoc "Versioned dialogue payloads shared by archive writers and authorized readers."

  @format "structured_agent_message_v1"
  @kinds [:accepted_input, :agent_output_generated, :participant_transcription_final]
  @maximum_encoded_bytes 16 * 1_024 * 1_024

  @spec wrap(map()) :: map()
  def wrap(content) when is_map(content), do: %{"content_format" => @format, "content" => content}

  @spec project(atom(), map(), String.t() | nil) :: map() | nil
  def project(kind, payload, participant_id) when kind in @kinds and is_map(payload) do
    case Map.fetch(payload, "content_format") do
      :error -> legacy(payload)
      {:ok, @format} -> structured(kind, decode(Map.get(payload, "content")), participant_id)
      {:ok, _unknown} -> nil
    end
  end

  def project(_kind, _payload, _participant_id), do: nil

  defp decode(content) when is_map(content), do: content

  defp decode(content) when is_binary(content) and byte_size(content) <= @maximum_encoded_bytes do
    case JSON.decode(content) do
      {:ok, value} when is_map(value) -> value
      _invalid -> nil
    end
  end

  defp decode(_content), do: nil

  defp structured(
         kind,
         %{
           "type" => "participant_message",
           "participant_id" => id,
           "agent_mode" => mode,
           "message" => text
         } = content,
         id
       )
       when is_binary(id) and mode in ["listener", "speaker"] and map_size(content) == 4 do
    if valid_text?(text) and bounded_content?(content, id, text) do
      projection = %{text: text, agent_mode: mode}

      if kind == :agent_output_generated,
        do:
          Map.put(
            projection,
            :output_purpose,
            if(mode == "listener", do: "backchannel", else: "main_response")
          ),
        else: projection
    end
  end

  defp structured(_kind, _content, _participant_id), do: nil

  defp bounded_content?(content, id, text) do
    byte_size(text) <= @maximum_encoded_bytes and byte_size(id) <= @maximum_encoded_bytes and
      valid_text?(id) and
      IO.iodata_length(JSON.encode_to_iodata!(content)) <= @maximum_encoded_bytes
  end

  defp legacy(payload) do
    text = Map.get(payload, "content") || Map.get(payload, "text")
    if valid_text?(text), do: %{text: text}
  end

  defp valid_text?(text) when is_binary(text), do: String.valid?(text) and String.trim(text) != ""
  defp valid_text?(_text), do: false
end
