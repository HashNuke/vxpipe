defmodule Vxpipe.Identity.OAuth.Profile do
  @moduledoc "Bounded public-client OAuth profile enforced before Boruta processes input."

  alias Vxpipe.Identity.ApiKeyActor

  @registration ~w(client_name redirect_uris grant_types response_types token_endpoint_auth_method scope client_uri)
  @authorization ~w(response_type client_id redirect_uri resource scope state code_challenge code_challenge_method)
  @code ~w(grant_type client_id redirect_uri resource code code_verifier)
  @refresh ~w(grant_type client_id refresh_token resource scope)
  @revocation ~w(client_id token token_type_hint)
  @grants ~w(authorization_code refresh_token)

  def registration(params) do
    if fields?(params, @registration) and valid_registration?(params) do
      {:ok,
       params
       |> Map.put_new("grant_types", @grants)
       |> Map.put_new("response_types", ["code"])
       |> Map.put("token_endpoint_auth_method", "none")
       |> Map.put("scope", "mcp")}
    else
      {:error, :invalid_client_metadata}
    end
  end

  def authorization(params, resource) do
    with :ok <- target(params, resource, true) do
      if fields?(params, @authorization) and valid_authorization?(params),
        do: {:ok, Map.put_new(params, "scope", "mcp")},
        else: {:error, :invalid_request}
    end
  end

  def token(%{"grant_type" => "authorization_code"} = params, resource) do
    with :ok <- target(params, resource, true) do
      if fields?(params, @code) and client_id?(params) and
           redirect_uri?(params["redirect_uri"]) and opaque?(params["code"]) and
           verifier?(params["code_verifier"]),
         do: {:ok, params},
         else: {:error, :invalid_request}
    end
  end

  def token(%{"grant_type" => "refresh_token"} = params, resource) do
    with :ok <- target(params, resource, false) do
      if fields?(params, @refresh) and client_id?(params) and
           opaque?(params["refresh_token"]) and scope?(params),
         do: {:ok, params},
         else: {:error, :invalid_request}
    end
  end

  def token(_params, _resource), do: {:error, :unsupported_grant_type}

  def revocation(params) do
    if fields?(params, @revocation) and client_id?(params) and opaque?(params["token"]) and
         Map.get(params, "token_type_hint") in [nil, "access_token", "refresh_token"],
       do: {:ok, params},
       else: {:error, :invalid_request}
  end

  @doc "Registration syntax only; authorization must also match a stored redirect exactly."
  def redirect_uri?(value) when is_binary(value) and byte_size(value) in 1..2_048 do
    with true <- clean_text?(value),
         false <- String.contains?(value, ["*", "\\", " "]),
         {:ok, uri} <- URI.new(value),
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment),
         true <- is_binary(uri.host) and uri.host != "",
         true <- is_integer(uri.port) and uri.port in 1..65_535 do
      uri.scheme == "https" or
        (uri.scheme == "http" and uri.host in ["127.0.0.1", "::1"])
    else
      _invalid -> false
    end
  end

  def redirect_uri?(_value), do: false

  defp valid_registration?(params) do
    name?(params["client_name"]) and redirects?(params["redirect_uris"]) and
      grants?(Map.get(params, "grant_types", @grants)) and
      Map.get(params, "response_types", ["code"]) == ["code"] and
      Map.get(params, "token_endpoint_auth_method", "none") == "none" and scope?(params) and
      optional_client_uri?(params["client_uri"])
  end

  defp valid_authorization?(params) do
    params["response_type"] == "code" and client_id?(params) and
      redirect_uri?(params["redirect_uri"]) and scope?(params) and
      params["code_challenge_method"] == "S256" and challenge?(params["code_challenge"]) and
      state?(params["state"])
  end

  defp fields?(params, allowed) when is_map(params),
    do: Enum.all?(Map.keys(params), &(&1 in allowed))

  defp fields?(_params, _allowed), do: false

  defp target(params, resource, required?) when is_map(params) do
    supplied = Map.get(params, "resource")

    if is_binary(resource) and resource != "" and
         (supplied == resource or (not required? and not Map.has_key?(params, "resource"))),
       do: :ok,
       else: {:error, :invalid_target}
  end

  defp target(_params, _resource, _required?), do: {:error, :invalid_request}

  defp client_id?(params), do: ApiKeyActor.valid_id?(params["client_id"])
  defp scope?(params), do: Map.get(params, "scope", "mcp") == "mcp"

  defp name?(value) when is_binary(value),
    do: byte_size(value) in 1..120 and String.trim(value) != "" and clean_text?(value)

  defp name?(_value), do: false

  defp redirects?(values) when is_list(values),
    do: length(values) in 1..5 and Enum.all?(values, &redirect_uri?/1)

  defp redirects?(_values), do: false

  defp grants?(values) when is_list(values),
    do:
      "authorization_code" in values and length(values) in 1..2 and
        Enum.all?(values, &(&1 in @grants))

  defp grants?(_values), do: false

  defp optional_client_uri?(nil), do: true
  defp optional_client_uri?(uri), do: redirect_uri?(uri)

  defp challenge?(value) when is_binary(value) and byte_size(value) == 43 do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} when byte_size(decoded) == 32 ->
        Base.url_encode64(decoded, padding: false) == value

      _invalid ->
        false
    end
  end

  defp challenge?(_value), do: false

  defp verifier?(value) when is_binary(value) and byte_size(value) in 43..128,
    do: Regex.match?(~r/\A[A-Za-z0-9._~-]+\z/, value)

  defp verifier?(_value), do: false

  defp opaque?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: Regex.match?(~r/\A[A-Za-z0-9._~+\/-]+=*\z/, value)

  defp opaque?(_value), do: false

  defp state?(nil), do: true
  defp state?(value) when is_binary(value), do: byte_size(value) <= 1_024 and clean_text?(value)
  defp state?(_value), do: false

  defp clean_text?(value),
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
