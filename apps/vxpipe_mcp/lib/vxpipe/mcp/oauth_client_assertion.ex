defmodule Vxpipe.MCP.OAuthClientAssertion do
  @moduledoc "Validated registered-client signing configuration; private key material never leaves the token adapter."
  alias ExMCP.Authorization.{ClientAssertion, JWT}
  alias Vxpipe.MCP.StaticConfiguration

  @derive {Inspect, only: []}
  @enforce_keys [:client_id, :token_endpoint, :key, :algorithm, :key_id]
  defstruct @enforce_keys

  @keys ~w(client_id token_endpoint private_key algorithm key_id)a

  defdelegate supported?(metadata),
    to: Vxpipe.MCP.OAuthCapabilities,
    as: :private_key_jwt_supported?

  def new(input, metadata) when is_map(input) and is_map(metadata) do
    with true <- Map.keys(input) -- @keys == [],
         true <- text?(input[:client_id], 2048),
         true <- is_nil(input[:key_id]) or text?(input[:key_id], 256),
         true <- input[:algorithm] in Vxpipe.MCP.OAuthCapabilities.client_assertion_algorithms(),
         true <- supported?(metadata, input.algorithm),
         true <- input[:token_endpoint] == metadata["token_endpoint"],
         {:ok, _} <- StaticConfiguration.endpoint(input[:token_endpoint]),
         {:ok, key} <- private_key(input[:private_key], input.algorithm) do
      {:ok,
       %__MODULE__{
         client_id: input.client_id,
         token_endpoint: input.token_endpoint,
         key: key,
         algorithm: input.algorithm,
         key_id: input[:key_id]
       }}
    else
      _ -> {:error, :invalid_oauth_client_assertion}
    end
  rescue
    _ -> {:error, :invalid_oauth_client_assertion}
  end

  def new(_, _), do: {:error, :invalid_oauth_client_assertion}

  def parameters(%__MODULE__{} = configured) do
    case ClientAssertion.build_assertion_params(
           client_id: configured.client_id,
           token_endpoint: configured.token_endpoint,
           private_key: configured.key,
           alg: configured.algorithm,
           kid: configured.key_id,
           lifetime: 60
         ) do
      {:ok, parameters} -> {:ok, parameters}
      _ -> {:error, :invalid_oauth_client_assertion}
    end
  rescue
    _ -> {:error, :invalid_oauth_client_assertion}
  end

  defp supported?(metadata, algorithm),
    do: Vxpipe.MCP.OAuthCapabilities.private_key_jwt_supported?(metadata, algorithm)

  defp private_key(pem, algorithm) when is_binary(pem) and byte_size(pem) in 1..16_384 do
    with {:ok, key} <- JWT.load_key(pem),
         true <- matching_key?(JWT.to_map(key), algorithm),
         do: {:ok, key}
  end

  defp private_key(_, _), do: {:error, :invalid_key}

  defp matching_key?(%{"kty" => "RSA", "n" => modulus, "d" => private}, algorithm)
       when algorithm in ["RS256", "PS256"] and is_binary(private) and byte_size(private) > 0 do
    with {:ok, bytes} <- Base.url_decode64(modulus, padding: false),
         value = :binary.decode_unsigned(bytes),
         do: value >= Integer.pow(2, 2047) and value < Integer.pow(2, 8192)
  end

  defp matching_key?(%{"kty" => "EC", "crv" => "P-256", "d" => private}, "ES256"),
    do: is_binary(private) and byte_size(private) > 0

  defp matching_key?(_, _), do: false

  defp text?(value, max),
    do:
      is_binary(value) and byte_size(value) in 1..max and
        String.valid?(value) and not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
