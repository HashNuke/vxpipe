defmodule Vxpipe.MCP.OAuthRequestParameters do
  @moduledoc "Bounded literal provider parameters; managed OAuth fields cannot be replaced."
  @reserved ~w(response_type client_id client_secret redirect_uri scope state code_challenge
    code_challenge_method resource audience grant_type code refresh_token access_token token_type
    client_assertion client_assertion_type authorization request request_uri response_mode assertion)

  def endpoint_query(endpoint) do
    with {:ok, uri} <- URI.new(endpoint) do
      (uri.query || "")
      |> URI.query_decoder()
      |> Enum.map(fn {name, value} -> %{"name" => name, "value" => value} end)
      |> validate()
    else
      _ -> {:error, :invalid_oauth_parameters}
    end
  rescue
    _ -> {:error, :invalid_oauth_parameters}
  end

  def validate(pairs, audience \\ nil)

  def validate(pairs, audience) when is_list(pairs) and length(pairs) <= 32 do
    with {:ok, parameters} <- collect(pairs),
         {:ok, audience} <- audience(audience),
         parameters = Map.merge(parameters, audience),
         true <-
           Enum.reduce(parameters, 0, fn {k, v}, size -> size + byte_size(k) + byte_size(v) end) <=
             16_384 do
      {:ok, parameters}
    else
      _ -> {:error, :invalid_oauth_parameters}
    end
  end

  def validate(_, _), do: {:error, :invalid_oauth_parameters}

  defp collect(pairs) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn
      %{"name" => name, "value" => value} = pair, {:ok, parameters} when map_size(pair) == 2 ->
        if name?(name) and text?(value, 8192) and not Map.has_key?(parameters, name),
          do: {:cont, {:ok, Map.put(parameters, name, value)}},
          else: {:halt, :invalid}

      _, _ ->
        {:halt, :invalid}
    end)
  end

  defp name?(name) when is_binary(name) and byte_size(name) in 1..64,
    do:
      Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_.:-]*\z/, name) and
        String.downcase(name) not in @reserved

  defp name?(_), do: false
  defp audience(nil), do: {:ok, %{}}

  defp audience(value) do
    if text?(value, 2048) and value != "", do: {:ok, %{"audience" => value}}, else: :invalid
  end

  defp text?(value, max),
    do:
      is_binary(value) and byte_size(value) <= max and String.valid?(value) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
