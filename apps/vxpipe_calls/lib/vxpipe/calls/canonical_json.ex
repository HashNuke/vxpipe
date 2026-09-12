defmodule Vxpipe.Calls.CanonicalJSON do
  @moduledoc false

  @spec encode!(term()) :: binary()
  def encode!(value), do: value |> encode_value() |> IO.iodata_to_binary()

  defp encode_value(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, entry} ->
        [JSON.encode_to_iodata!(key), ?:, encode_value(entry)]
      end)

    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp encode_value(value) when is_list(value) do
    [?[, value |> Enum.map(&encode_value/1) |> Enum.intersperse(?,), ?]]
  end

  defp encode_value(value), do: JSON.encode_to_iodata!(value)
end
