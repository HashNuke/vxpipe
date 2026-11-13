defmodule Vxpipe.Providers.ElevenLabs.Voices do
  @moduledoc "Account-scoped TTS voice discovery; independent of speech sessions."
  alias Vxpipe.CallEngine.VoiceCatalog.{HTTP, Query}

  @labels [
    {"gender", "Gender"},
    {"age", "Age"},
    {"accent", "Accent"},
    {"language", "Language"},
    {"use_case", "Use case"}
  ]
  def filters do
    [
      %{
        key: "gender",
        label: "Gender",
        type: "select",
        options:
          Enum.map(["male", "female", "neutral"], &%{value: &1, label: String.capitalize(&1)})
      },
      %{key: "language", label: "Language", type: "text"},
      %{key: "accent", label: "Accent", type: "text"}
    ]
  end

  def list(scope, query, payload, options) do
    params =
      Map.merge(query.filters, %{
        "search" => query.search,
        "page_size" => Query.page_size(),
        "include_total_count" => false
      })

    params = if query.cursor, do: Map.put(params, "next_page_token", query.cursor), else: params

    with {:ok, body} <-
           HTTP.get("https://api.elevenlabs.io/v2/voices", headers(payload), params, options),
         {:ok, cursor} <- cursor(body),
         voices when is_list(voices) and length(voices) <= 100 <- Map.get(body, "voices"),
         {:ok, entries} <- entries(voices, scope.model) do
      {:ok, %{voices: entries, nextCursor: cursor}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_voice_catalog_response}
    end
  end

  def get(scope, id, payload, options) do
    case HTTP.get("https://api.elevenlabs.io/v1/voices/" <> id, headers(payload), %{}, options) do
      {:ok, body} ->
        with {:ok, entry} <- entry(body) do
          if entry.id == id and compatible?(body, scope.model), do: {:ok, entry}, else: {:ok, nil}
        end

      {:error, :voice_not_found} ->
        {:ok, nil}

      error ->
        error
    end
  end

  defp headers(%{"api_key" => key}), do: [{"xi-api-key", key}]
  defp cursor(%{"has_more" => false}), do: {:ok, nil}

  defp cursor(%{"has_more" => true, "next_page_token" => token})
       when is_binary(token) and byte_size(token) in 1..2048, do: {:ok, token}

  defp cursor(_), do: {:error, :invalid_voice_catalog_response}

  defp entries(voices, model) do
    Enum.reduce_while(voices, {:ok, []}, fn voice, {:ok, acc} ->
      case entry(voice) do
        {:ok, value} ->
          {:cont, {:ok, if(compatible?(voice, model), do: [value | acc], else: acc)}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp entry(%{"voice_id" => id, "name" => name} = voice) do
    description = Map.get(voice, "description") || ""
    labels = Map.get(voice, "labels") || %{}

    if Query.valid_id?(id) and Query.text?(name, 256) and String.trim(name) != "" and
         Query.text?(description, 4096) and is_map(labels) do
      attributes =
        Enum.flat_map(@labels, fn {key, label} ->
          value = Map.get(labels, key)

          if is_binary(value) and byte_size(value) in 1..128,
            do: [%{key: key, label: label, value: value}],
            else: []
        end)

      {:ok, %{id: id, name: name, description: description, attributes: attributes}}
    else
      {:error, :invalid_voice_catalog_response}
    end
  end

  defp entry(_), do: {:error, :invalid_voice_catalog_response}

  defp compatible?(%{"category" => "professional", "fine_tuning" => %{"state" => states}}, model)
       when is_map(states),
       do: Map.get(states, model) == "fine_tuned"

  defp compatible?(_, _), do: true
end
