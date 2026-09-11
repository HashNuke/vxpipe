defmodule Vxpipe.Console.HTTPByteRange do
  @moduledoc "Selects one satisfiable byte range for a finite response body."

  @type selection :: %{
          required(:first) => non_neg_integer(),
          required(:last) => non_neg_integer(),
          required(:status) => 200 | 206
        }

  @spec parse(nil | String.t(), pos_integer()) ::
          {:ok, selection()} | {:error, :range_not_satisfiable}
  def parse(nil, total_bytes) when is_integer(total_bytes) and total_bytes > 0 do
    {:ok, %{first: 0, last: total_bytes - 1, status: 200}}
  end

  def parse(header, total_bytes)
      when is_binary(header) and is_integer(total_bytes) and total_bytes > 0 do
    with "bytes=" <> requested <- String.trim(header),
         false <- String.contains?(requested, ","),
         [first, last] <- String.split(requested, "-", parts: 2),
         {:ok, selection} <- selection(first, last, total_bytes) do
      {:ok, Map.put(selection, :status, 206)}
    else
      _invalid -> {:error, :range_not_satisfiable}
    end
  end

  def parse(_header, _total_bytes), do: {:error, :range_not_satisfiable}

  defp selection("", "", _total_bytes), do: {:error, :range_not_satisfiable}

  defp selection("", suffix, total_bytes) do
    with {:ok, count} <- integer(suffix),
         true <- count > 0 do
      {:ok, %{first: max(total_bytes - count, 0), last: total_bytes - 1}}
    else
      _invalid -> {:error, :range_not_satisfiable}
    end
  end

  defp selection(first, "", total_bytes) do
    with {:ok, first} <- integer(first),
         true <- first < total_bytes do
      {:ok, %{first: first, last: total_bytes - 1}}
    else
      _invalid -> {:error, :range_not_satisfiable}
    end
  end

  defp selection(first, last, total_bytes) do
    with {:ok, first} <- integer(first),
         {:ok, last} <- integer(last),
         true <- first <= last and first < total_bytes do
      {:ok, %{first: first, last: min(last, total_bytes - 1)}}
    else
      _invalid -> {:error, :range_not_satisfiable}
    end
  end

  defp integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _invalid -> {:error, :invalid_integer}
    end
  end
end
