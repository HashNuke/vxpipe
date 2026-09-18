defmodule Vxpipe.CallEngine.CallSpecValidation do
  @moduledoc false

  alias Vxpipe.CallEngine.Error

  @identifier_pattern ~r/\A[A-Za-z0-9_-]{1,128}\z/

  def normalize_map(value, allowed, code, message, path) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, field_value}, {:ok, normalized} ->
      case known_key(key, allowed) do
        {:ok, normalized_key} ->
          if Map.has_key?(normalized, normalized_key) do
            {:halt,
             invalid(code, message, path ++ [Atom.to_string(normalized_key)], "is duplicated")}
          else
            {:cont, {:ok, Map.put(normalized, normalized_key, field_value)}}
          end

        :error ->
          {:halt, invalid(code, message, path ++ [display_key(key)], "is not supported")}
      end
    end)
  end

  def normalize_map(_value, _allowed, code, message, path) do
    invalid(code, message, path, "must be an object")
  end

  def fetch(map, key, code, message, path) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> invalid(code, message, path ++ [Atom.to_string(key)], "is required")
    end
  end

  def string(value, code, message, path, options \\ []) do
    maximum = Keyword.get(options, :maximum, 4_096)

    if is_binary(value) and String.valid?(value) and String.trim(value) != "" and
         byte_size(value) <= maximum do
      {:ok, value}
    else
      invalid(code, message, path, "must be a non-empty string of at most #{maximum} bytes")
    end
  end

  def optional_string(nil, _code, _message, _path, _options), do: {:ok, nil}

  def optional_string(value, code, message, path, options) do
    string(value, code, message, path, options)
  end

  def identifier(value, code, message, path) when is_binary(value) do
    if Regex.match?(@identifier_pattern, value) do
      {:ok, value}
    else
      invalid(code, message, path, "must contain 1-128 URL-safe identifier characters")
    end
  end

  def identifier(_value, code, message, path) do
    invalid(code, message, path, "must be a string")
  end

  def positive_integer(value, _code, _message, _path) when is_integer(value) and value > 0,
    do: {:ok, value}

  def positive_integer(_value, code, message, path) do
    invalid(code, message, path, "must be a positive integer")
  end

  def enum(value, values, code, message, path) do
    case Enum.find(values, fn {_normalized, external} -> value == external end) do
      {normalized, _external} -> {:ok, normalized}
      nil -> invalid(code, message, path, "must be a supported value")
    end
  end

  def invalid(code, message, path, reason) do
    {:error, Error.new(code, message, details: %{"path" => path, "reason" => reason})}
  end

  def private_data?(value) when is_map(value) do
    Enum.any?(value, fn {key, nested} -> private_key?(key) or private_data?(nested) end)
  end

  def private_data?(value) when is_list(value), do: Enum.any?(value, &private_data?/1)
  def private_data?(_value), do: false

  defp known_key(key, allowed) do
    Enum.find_value(allowed, :error, fn allowed_key ->
      if key == allowed_key or key == Atom.to_string(allowed_key), do: {:ok, allowed_key}
    end)
  end

  defp display_key(key) when is_atom(key), do: Atom.to_string(key)
  defp display_key(key) when is_binary(key), do: key
  defp display_key(_key), do: "<invalid-key>"

  defp private_key?(key) when is_atom(key), do: private_key?(Atom.to_string(key))

  defp private_key?(key) when is_binary(key) do
    normalized = String.downcase(key)

    Enum.any?(["api_key", "authorization", "password", "secret", "token"], fn name ->
      normalized == name or String.ends_with?(normalized, "_#{name}")
    end)
  end

  defp private_key?(_key), do: false
end
