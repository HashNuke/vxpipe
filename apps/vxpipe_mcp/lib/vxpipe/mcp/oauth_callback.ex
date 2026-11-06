defmodule Vxpipe.MCP.OAuthCallback do
  @moduledoc "Private authorization response parsing and issuer checks; does not claim state or redeem codes."
  @derive {Inspect, only: []}
  defstruct [:state, :code, :error, :issuer]

  def parse(query) when is_binary(query) and byte_size(query) <= 16_384 do
    pairs = Enum.to_list(URI.query_decoder(query))
    params = Map.new(pairs)

    with true <- length(pairs) == map_size(params),
         true <- text?(params["state"], 32, 256),
         true <- response?(params),
         true <- not Map.has_key?(params, "iss") or text?(params["iss"], 1, 2048) do
      {:ok,
       %__MODULE__{
         state: params["state"],
         code: params["code"],
         error: params["error"],
         issuer: params["iss"]
       }}
    else
      _ -> {:error, :invalid_oauth_callback}
    end
  rescue
    _ -> {:error, :invalid_oauth_callback}
  end

  def parse(_query), do: {:error, :invalid_oauth_callback}

  def validate(%__MODULE__{} = callback, issuer, required?)
      when is_binary(issuer) and is_boolean(required?) do
    cond do
      callback.issuer != issuer ->
        {:error, :oauth_issuer_mismatch}

      callback.error == "access_denied" ->
        {:error, :oauth_consent_denied}

      not is_nil(callback.error) ->
        {:error, :oauth_authorization_failed}

      text?(callback.code, 1, 8192) ->
        {:ok, callback.code}

      true ->
        {:error, :invalid_oauth_callback}
    end
  end

  def validate(_callback, _issuer, _required), do: {:error, :invalid_oauth_callback}

  defp response?(params) do
    case {Map.has_key?(params, "code"), Map.has_key?(params, "error")} do
      {true, false} -> text?(params["code"], 1, 8192)
      {false, true} -> text?(params["error"], 1, 256)
      _ -> false
    end
  end

  defp text?(value, min, max),
    do:
      is_binary(value) and byte_size(value) >= min and byte_size(value) <= max and
        String.valid?(value)
end
