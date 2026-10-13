defmodule Vxpipe.Identity.Email do
  @moduledoc "Login identifier normalization. Email is never a delivery channel."

  @max_length 320

  @spec normalize(term()) :: {:ok, String.t()} | {:error, :invalid_email}
  def normalize(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if valid?(normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_email}
    end
  end

  def normalize(_), do: {:error, :invalid_email}

  defp valid?(email) do
    byte_size(email) in 3..@max_length and Regex.match?(~r/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, email)
  end
end
