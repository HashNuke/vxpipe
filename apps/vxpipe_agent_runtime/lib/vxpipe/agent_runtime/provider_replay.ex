defmodule Vxpipe.AgentRuntime.ProviderReplay do
  @moduledoc "Bounds private provider protocol data retained with native assistant exchanges."

  @maximum_bytes 65_536
  @maximum_depth 32

  @spec validate(term()) :: :ok | {:error, atom()}
  def validate(value) when is_map(value) and not is_struct(value) do
    if json_value?(value, @maximum_depth) do
      if byte_size(JSON.encode!(value)) <= @maximum_bytes,
        do: :ok,
        else: {:error, :provider_replay_too_large}
    else
      {:error, :invalid_provider_replay}
    end
  rescue
    _error -> {:error, :invalid_provider_replay}
  end

  def validate(_value), do: {:error, :invalid_provider_replay}

  defp json_value?(_value, 0), do: false
  defp json_value?(nil, _depth), do: true
  defp json_value?(value, _depth) when is_boolean(value) or is_number(value), do: true
  defp json_value?(value, _depth) when is_binary(value), do: String.valid?(value)

  defp json_value?(value, depth) when is_list(value),
    do: Enum.all?(value, &json_value?(&1, depth - 1))

  defp json_value?(value, depth) when is_map(value) and not is_struct(value),
    do:
      Enum.all?(value, fn {key, item} ->
        is_binary(key) and String.valid?(key) and json_value?(item, depth - 1)
      end)

  defp json_value?(_value, _depth), do: false
end
