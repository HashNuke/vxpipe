defmodule Vxpipe.Gateway.Telephony.Twilio.Form do
  @moduledoc false

  @maximum_fields 128
  @maximum_key_bytes 128
  @maximum_value_bytes 8_192

  @spec decode(binary()) :: {:ok, %{String.t() => String.t()}} | {:error, :invalid_twilio_form}
  def decode(body) when is_binary(body) do
    body
    |> URI.query_decoder()
    |> Enum.reduce_while({:ok, %{}}, &put_field/2)
  rescue
    _exception -> {:error, :invalid_twilio_form}
  end

  def decode(_invalid), do: {:error, :invalid_twilio_form}

  defp put_field({key, value}, {:ok, fields}) do
    if valid_field?(key, value) and map_size(fields) < @maximum_fields and
         not Map.has_key?(fields, key) do
      {:cont, {:ok, Map.put(fields, key, value)}}
    else
      {:halt, {:error, :invalid_twilio_form}}
    end
  end

  defp valid_field?(key, value) do
    is_binary(key) and byte_size(key) > 0 and byte_size(key) <= @maximum_key_bytes and
      is_binary(value) and byte_size(value) <= @maximum_value_bytes
  end
end
