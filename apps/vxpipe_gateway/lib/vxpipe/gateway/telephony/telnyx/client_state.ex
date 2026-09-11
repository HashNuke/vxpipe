defmodule Vxpipe.Gateway.Telephony.Telnyx.ClientState do
  @moduledoc false

  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
  @maximum_encoded_bytes 1_024

  @spec encode(String.t()) :: String.t()
  def encode(leg_id) when is_binary(leg_id) do
    %{"vxpipe_leg_id" => leg_id}
    |> JSON.encode!()
    |> Base.encode64()
  end

  @spec decode(term()) :: {:ok, String.t()} | {:error, :invalid_client_state}
  def decode(encoded)
      when is_binary(encoded) and byte_size(encoded) > 0 and
             byte_size(encoded) <= @maximum_encoded_bytes do
    with {:ok, decoded} <- Base.decode64(encoded),
         {:ok, state} when is_map(state) <- JSON.decode(decoded),
         true <- map_size(state) == 1,
         {:ok, leg_id} <- Map.fetch(state, "vxpipe_leg_id"),
         true <- is_binary(leg_id) and Regex.match?(@identifier, leg_id) do
      {:ok, leg_id}
    else
      _invalid -> {:error, :invalid_client_state}
    end
  end

  def decode(_invalid), do: {:error, :invalid_client_state}
end
