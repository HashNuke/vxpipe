defmodule Vxpipe.Identity.Password do
  @moduledoc """
  Password policy: 15–128 characters, exact input bytes preserved.
  No trimming, truncation, or composition rules.
  """

  @min_length 15
  @max_length 128
  @max_bytes 1024

  @spec validate(term()) :: :ok | {:error, :too_short | :too_long | :invalid_password}
  def validate(password) when is_binary(password) do
    cond do
      byte_size(password) > @max_bytes -> {:error, :too_long}
      String.length(password) < @min_length -> {:error, :too_short}
      String.length(password) > @max_length -> {:error, :too_long}
      not String.valid?(password) -> {:error, :invalid_password}
      true -> :ok
    end
  end

  def validate(_), do: {:error, :invalid_password}

  @spec confirm(term(), term()) :: :ok | {:error, atom()}
  def confirm(password, confirmation) do
    with :ok <- validate(password) do
      if password == confirmation, do: :ok, else: {:error, :confirmation_mismatch}
    end
  end
end
