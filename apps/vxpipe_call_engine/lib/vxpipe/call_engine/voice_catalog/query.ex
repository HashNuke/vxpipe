defmodule Vxpipe.CallEngine.VoiceCatalog.Query do
  @moduledoc false
  @page_size 50
  def page_size, do: @page_size

  def valid_id?(id),
    do:
      is_binary(id) and byte_size(id) in 1..128 and
        Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/, id)

  def parse(query, descriptors) when is_map(query) do
    search = Map.get(query, "search", "")
    filters = Map.get(query, "filters", %{})
    cursor = Map.get(query, "cursor")

    if Map.keys(query) -- ["search", "filters", "cursor"] == [] and
         text?(search, 256) and (is_nil(cursor) or text?(cursor, 2048)) and
         is_map(filters) and map_size(filters) <= length(descriptors) and
         Enum.all?(filters, &valid_filter?(&1, descriptors)) do
      {:ok, %{search: search, filters: filters, cursor: cursor}}
    else
      {:error, :invalid_voice_query}
    end
  end

  def parse(_, _), do: {:error, :invalid_voice_query}

  def page(voices, query) do
    with {:ok, offset} <- offset(query.cursor) do
      matches = Enum.filter(voices, &matches?(&1, query))
      next = offset + @page_size

      {:ok,
       %{
         voices: Enum.slice(matches, offset, @page_size),
         nextCursor: if(next < length(matches), do: Integer.to_string(next)),
         total: length(matches)
       }}
    end
  end

  def text?(value, max), do: is_binary(value) and byte_size(value) <= max and String.valid?(value)

  defp valid_filter?({key, value}, descriptors) do
    case Enum.find(descriptors, &(&1.key == key)) do
      %{type: "text"} ->
        text?(value, 128)

      %{type: "boolean"} ->
        is_boolean(value)

      %{type: "select", options: options} ->
        is_binary(value) and Enum.any?(options, &(&1.value == value))

      _ ->
        false
    end
  end

  defp offset(nil), do: {:ok, 0}

  defp offset(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 and n <= 10_000 -> {:ok, n}
      _ -> {:error, :invalid_voice_query}
    end
  end

  defp matches?(voice, query) do
    text =
      Enum.join(
        [
          voice.id,
          voice.name,
          Map.get(voice, :description, "") | Enum.map(voice.attributes, & &1.value)
        ],
        " "
      )

    String.contains?(String.downcase(text), String.downcase(query.search)) and
      Enum.all?(query.filters, fn {key, value} ->
        Enum.any?(voice.attributes, &(&1.key == key and &1.value == value))
      end)
  end
end
