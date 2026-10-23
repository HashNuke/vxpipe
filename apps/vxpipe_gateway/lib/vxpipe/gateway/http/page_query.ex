defmodule Vxpipe.Gateway.HTTP.PageQuery do
  @moduledoc "Parses bounded page-number query parameters for canonical product lists."

  def parse(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["page", "page_size"])),
         {:ok, page} <- integer(Map.get(params, "page", "1"), 2_147_483_647),
         {:ok, size} <- integer(Map.get(params, "page_size", "25"), 50) do
      {:ok, page, size}
    else
      _invalid -> {:error, :invalid_page}
    end
  end

  defp integer(value, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 1 and number <= maximum -> {:ok, number}
      _invalid -> {:error, :invalid_page}
    end
  end

  defp integer(_value, _maximum), do: {:error, :invalid_page}
end
