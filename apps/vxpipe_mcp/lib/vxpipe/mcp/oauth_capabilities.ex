defmodule Vxpipe.MCP.OAuthCapabilities do
  @moduledoc "Bounded OAuth metadata fields and the installation's supported grant capabilities."
  @arrays ~w(response_types_supported grant_types_supported code_challenge_methods_supported token_endpoint_auth_methods_supported)
  @booleans ~w(client_id_metadata_document_supported authorization_response_iss_parameter_supported)
  @algorithms ~w(RS256 PS256 ES256)

  def client_assertion_algorithms, do: @algorithms

  def validate(metadata) when is_map(metadata) do
    if Enum.all?(@arrays, fn field ->
         optional?(metadata, field, fn values -> list?(values, 32, &text?/1) end)
       end) and
         Enum.all?(@booleans, &optional?(metadata, &1, fn value -> is_boolean(value) end)) and
         optional?(metadata, "scopes_supported", &valid_scopes?/1) and signing_metadata?(metadata),
       do: :ok,
       else: {:error, :invalid_oauth_metadata}
  end

  def validate(_metadata), do: {:error, :invalid_oauth_metadata}

  def authorization_code(metadata) do
    if validate(metadata) == :ok and
         "S256" in Map.get(metadata, "code_challenge_methods_supported", []) and
         "code" in Map.get(metadata, "response_types_supported", []) and
         "authorization_code" in Map.get(metadata, "grant_types_supported", [
           "authorization_code",
           "implicit"
         ]) and
         metadata["authorization_response_iss_parameter_supported"] == true,
       do: :ok,
       else: {:error, :unsupported_oauth_capabilities}
  end

  def supported_grants(metadata) do
    if validate(metadata) == :ok do
      browser = if authorization_code(metadata) == :ok, do: ["authorization_code"], else: []

      methods =
        Map.get(metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"])

      machine? =
        "client_credentials" in Map.get(metadata, "grant_types_supported", []) and
          (Enum.any?(methods, &(&1 in ["client_secret_basic", "client_secret_post"])) or
             private_key_jwt_supported?(metadata))

      browser ++ if(machine?, do: ["client_credentials"], else: [])
    else
      []
    end
  end

  def private_key_jwt_supported?(metadata),
    do: Enum.any?(@algorithms, &private_key_jwt_supported?(metadata, &1))

  def private_key_jwt_supported?(metadata, algorithm) do
    validate(metadata) == :ok and algorithm in @algorithms and
      "private_key_jwt" in Map.get(metadata, "token_endpoint_auth_methods_supported", []) and
      algorithm in Map.get(metadata, "token_endpoint_auth_signing_alg_values_supported", [])
  end

  def valid_scopes?(values), do: list?(values, 64, &scope_token?/1)

  def challenge_scope?(value) when is_binary(value) and byte_size(value) in 1..8192,
    do: valid_scopes?(String.split(value, " "))

  def challenge_scope?(_value), do: false

  defp scope_token?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: Enum.all?(:binary.bin_to_list(value), &(&1 == 33 or &1 in 35..91 or &1 in 93..126))

  defp scope_token?(_value), do: false

  defp optional?(metadata, field, valid?) do
    case Map.fetch(metadata, field) do
      :error -> true
      {:ok, value} -> valid?.(value)
    end
  end

  defp list?(values, limit, valid?) when is_list(values),
    do: length(values) <= limit and Enum.all?(values, valid?)

  defp list?(_values, _limit, _valid?), do: false

  defp text?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1f\x7f]/, value)

  defp text?(_value), do: false

  defp signing_metadata?(metadata) do
    methods = Map.get(metadata, "token_endpoint_auth_methods_supported", [])
    required? = Enum.any?(methods, &(&1 in ["private_key_jwt", "client_secret_jwt"]))

    case Map.fetch(metadata, "token_endpoint_auth_signing_alg_values_supported") do
      :error -> not required?
      {:ok, algorithms} -> algorithms != [] and list?(algorithms, 32, &algorithm?/1)
    end
  end

  defp algorithm?(value) when is_binary(value) and byte_size(value) in 1..32,
    do: Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value)

  defp algorithm?(_value), do: false
end
