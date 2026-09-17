defmodule Vxpipe.Console.AdminPageParameter do
  @moduledoc false

  def parse(%{"page" => page}) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} when value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_page}
    end
  end

  def parse(%{"page" => _structured}), do: {:error, :invalid_page}
  def parse(_params), do: {:ok, 1}
end
