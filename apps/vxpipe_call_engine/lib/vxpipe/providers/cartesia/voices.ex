defmodule Vxpipe.Providers.Cartesia.Voices do
  @moduledoc "Account-scoped voice discovery for the installed Sonic models."
  alias Vxpipe.CallEngine.VoiceCatalog.{HTTP, Query}
  alias Vxpipe.Providers.Cartesia.TTS

  def filters do
    [
      %{key: "language", label: "Language", type: "text"},
      %{
        key: "gender",
        label: "Gender",
        type: "select",
        options:
          Enum.map(
            ~w(feminine masculine gender_neutral),
            &%{value: &1, label: String.replace(&1, "_", " ") |> String.capitalize()}
          )
      },
      %{key: "is_owner", label: "My voices", type: "boolean"}
    ]
  end

  def list(scope, query, payload, options) do
    params = Map.merge(query.filters, %{"q" => query.search, "limit" => Query.page_size()})
    params = if query.cursor, do: Map.put(params, "starting_after", query.cursor), else: params

    with {:ok, body} <-
           HTTP.get("https://api.cartesia.ai/voices", headers(payload), params, options),
         {:ok, cursor} <- cursor(body),
         rows when is_list(rows) and length(rows) <= 100 <- Map.get(body, "data"),
         {:ok, voices} <- entries(rows, scope.model) do
      {:ok, %{voices: voices, nextCursor: cursor}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_voice_catalog_response}
    end
  end

  def get(scope, id, payload, options) do
    case HTTP.get("https://api.cartesia.ai/voices/" <> id, headers(payload), %{}, options) do
      {:ok, %{"id" => ^id} = body} -> entry(body, scope.model)
      {:ok, _} -> {:error, :invalid_voice_catalog_response}
      {:error, :voice_not_found} -> {:ok, nil}
      error -> error
    end
  end

  defp headers(%{"api_key" => key}),
    do: [{"authorization", "Bearer " <> key}, {"cartesia-version", TTS.cartesia_version()}]

  defp cursor(%{"has_more" => false}), do: {:ok, nil}

  defp cursor(%{"has_more" => true, "next_page" => id}) do
    if Query.valid_id?(id), do: {:ok, id}, else: {:error, :invalid_voice_catalog_response}
  end

  defp cursor(_), do: {:error, :invalid_voice_catalog_response}

  defp entries(rows, model) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, voices} ->
      case entry(row, model) do
        {:ok, nil} -> {:cont, {:ok, voices}}
        {:ok, voice} -> {:cont, {:ok, [voice | voices]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, voices} -> {:ok, Enum.reverse(voices)}
      error -> error
    end
  end

  defp entry(%{"status" => status}, _) when status in ["archived", "pending", "failed"],
    do: {:ok, nil}

  defp entry(%{"id" => id, "name" => name, "status" => "active"} = row, model) do
    description = Map.get(row, "description") || ""

    with {:ok, _} <- TTS.public_options(model: model, voice: id),
         true <-
           Query.text?(name, 256) and String.trim(name) != "" and Query.text?(description, 4096) do
      attributes =
        Enum.flat_map(~w(language gender), fn key ->
          value = Map.get(row, key)

          if is_binary(value) and byte_size(value) in 1..128,
            do: [%{key: key, label: String.capitalize(key), value: value}],
            else: []
        end)

      {:ok, %{id: id, name: name, description: description, attributes: attributes}}
    else
      _ -> {:error, :invalid_voice_catalog_response}
    end
  end

  defp entry(_, _), do: {:error, :invalid_voice_catalog_response}
end
