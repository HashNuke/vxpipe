defmodule Vxpipe.Persistence.CredentialKeyring do
  @moduledoc "Externally supplied AES-256 keys. Key IDs are immutable; retired keys permit existing rows to decrypt."

  @derive {Inspect, only: [:current_key_id]}
  @enforce_keys [:current_key_id, :keys]
  defstruct @enforce_keys

  @type t :: %__MODULE__{current_key_id: String.t(), keys: %{String.t() => binary()}}

  @spec new(term(), term()) :: {:ok, t()} | {:error, :invalid_credential_keyring}
  def new(current_key_id, keys) when is_map(keys) and not is_struct(keys) do
    if map_size(keys) in 1..32 and Map.has_key?(keys, current_key_id) and
         Enum.all?(keys, fn {id, key} ->
           valid_id?(id) and is_binary(key) and byte_size(key) == 32
         end) do
      {:ok, %__MODULE__{current_key_id: current_key_id, keys: keys}}
    else
      {:error, :invalid_credential_keyring}
    end
  end

  def new(_id, _keys), do: {:error, :invalid_credential_keyring}

  @spec from_config(term(), term()) :: {:ok, t() | nil} | {:error, :invalid_credential_keyring}
  def from_config(nil, nil), do: {:ok, nil}

  def from_config(id, encoded)
      when is_binary(id) and is_binary(encoded) and byte_size(encoded) <= 16_384 do
    with {:ok, keys} when is_map(keys) and map_size(keys) in 1..32 <- JSON.decode(encoded),
         {:ok, keys} <- decode_keys(keys) do
      new(id, keys)
    else
      _invalid -> {:error, :invalid_credential_keyring}
    end
  end

  def from_config(_id, _encoded), do: {:error, :invalid_credential_keyring}

  def current(%__MODULE__{current_key_id: id} = keyring) do
    with {:ok, key} <- fetch(keyring, id), do: {:ok, id, key}
  end

  def current(_keyring), do: {:error, :credential_key_unavailable}

  def fetch(%__MODULE__{keys: keys}, id) do
    case Map.fetch(keys, id) do
      {:ok, key} when is_binary(key) and byte_size(key) == 32 -> {:ok, key}
      _unavailable -> {:error, :credential_key_unavailable}
    end
  end

  def fetch(_keyring, _id), do: {:error, :credential_key_unavailable}

  defp decode_keys(keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn
      {id, encoded}, {:ok, decoded} when is_binary(encoded) ->
        case Base.decode64(encoded) do
          {:ok, key} -> {:cont, {:ok, Map.put(decoded, id, key)}}
          :error -> {:halt, {:error, :invalid_credential_keyring}}
        end

      _invalid, _decoded ->
        {:halt, {:error, :invalid_credential_keyring}}
    end)
  end

  defp valid_id?(id),
    do: is_binary(id) and byte_size(id) <= 64 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id)
end
