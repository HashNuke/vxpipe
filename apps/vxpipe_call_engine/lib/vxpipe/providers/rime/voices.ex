defmodule Vxpipe.Providers.Rime.Voices do
  @moduledoc "Public Coda catalog, restricted to the adapter's default English language."
  alias Vxpipe.CallEngine.VoiceCatalog.{HTTP, Query}
  alias Vxpipe.Providers.Rime.TTS

  def filters do
    [
      %{
        key: "gender",
        label: "Gender",
        type: "select",
        options: Enum.map(~w(Female Male), &%{value: &1, label: &1})
      },
      %{key: "country", label: "Country", type: "text"}
    ]
  end

  def list(scope, query, _payload, options) do
    with {:ok, voices} <- catalog(scope.model, options), do: Query.page(voices, query)
  end

  def get(scope, id, _payload, options) do
    with {:ok, voices} <- catalog(scope.model, options),
         do: {:ok, Enum.find(voices, &(&1.id == id))}
  end

  defp catalog(model, options) do
    with {:ok, rows} <-
           HTTP.get("https://users.rime.ai/data/voices/voice_details.json", [], %{}, options),
         true <- is_list(rows) and length(rows) <= 5_000 and Enum.all?(rows, &valid_row?/1) do
      rows
      |> Enum.filter(&match?(%{"modelId" => ^model, "lang" => "eng"}, &1))
      |> Enum.reduce_while({:ok, []}, fn row, {:ok, voices} ->
        case entry(row, model) do
          {:ok, voice} -> {:cont, {:ok, [voice | voices]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, voices} -> {:ok, voices |> Enum.reverse() |> Enum.uniq_by(& &1.id)}
        error -> error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_voice_catalog_response}
    end
  end

  defp valid_row?(%{"modelId" => model, "lang" => lang, "speaker" => id}),
    do: Query.text?(model, 128) and Query.text?(lang, 16) and Query.valid_id?(id)

  defp valid_row?(_), do: false

  defp entry(%{"speaker" => id} = row, model) do
    description = Map.get(row, "description") || ""

    with {:ok, _} <- TTS.public_options(model: model, speaker: id),
         true <- Query.text?(description, 4096) do
      attributes =
        Enum.flat_map(~w(gender age country dialect), fn key ->
          value = Map.get(row, key)

          if is_binary(value) and byte_size(value) in 1..128,
            do: [%{key: key, label: String.capitalize(key), value: value}],
            else: []
        end)

      {:ok,
       %{id: id, name: String.capitalize(id), description: description, attributes: attributes}}
    else
      _ -> {:error, :invalid_voice_catalog_response}
    end
  end

  defp entry(_, _), do: {:error, :invalid_voice_catalog_response}
end
