defmodule Vxpipe.Console.MCPOAuthTokenRequest do
  @moduledoc "Projects encrypted saved client configuration into a private protocol request."
  alias Vxpipe.MCP.OAuthClientAssertion

  @methods %{
    "none" => :none,
    "client_secret_basic" => :client_secret_basic,
    "client_secret_post" => :client_secret_post,
    "private_key_jwt" => :private_key_jwt
  }

  def build(secrets, resource) when is_map(secrets) do
    with {:ok, method} <- Map.fetch(@methods, secrets["auth_method"]),
         {:ok, authentication} <- authentication(method, secrets) do
      {:ok,
       Map.merge(authentication, %{
         token_endpoint: secrets["token_endpoint"],
         client_id: secrets["client_id"],
         auth_method: method,
         resource: resource,
         parameters: Map.get(secrets, "token_parameters", []),
         audience: secrets["audience"]
       })}
    else
      _ -> {:error, :invalid_oauth_token_request}
    end
  rescue
    _ -> {:error, :invalid_oauth_token_request}
  end

  def build(_, _), do: {:error, :invalid_oauth_token_request}

  def machine(
        %{"registration_method" => "own_client", "grant_type" => "client_credentials"} = secrets
      ) do
    with %{"issuer" => issuer, "token_endpoint" => endpoint} = metadata <-
           secrets["machine_metadata"],
         true <-
           is_binary(issuer) and issuer == secrets["issuer"] and
             endpoint == secrets["token_endpoint"],
         scopes when is_list(scopes) and length(scopes) <= 64 <- Map.get(secrets, "scopes", []),
         true <- Enum.all?(scopes, &is_binary/1),
         {:ok, request} <- build(secrets, secrets["resource"]) do
      request =
        if scopes == [], do: request, else: Map.put(request, :scope, Enum.join(scopes, " "))

      {:ok, request, metadata}
    else
      _ -> {:error, :invalid_oauth_client_credentials}
    end
  end

  def machine(_), do: {:error, :invalid_oauth_client_credentials}

  defp authentication(:none, _secrets), do: {:ok, %{}}

  defp authentication(:private_key_jwt, secrets) do
    input = %{
      client_id: secrets["client_id"],
      token_endpoint: secrets["token_endpoint"],
      private_key: secrets["private_key"],
      algorithm: secrets["algorithm"],
      key_id: secrets["key_id"]
    }

    metadata = %{
      "token_endpoint" => secrets["token_endpoint"],
      "token_endpoint_auth_methods_supported" => ["private_key_jwt"],
      "token_endpoint_auth_signing_alg_values_supported" => secrets["signing_algorithms"]
    }

    with {:ok, signing} <- OAuthClientAssertion.new(input, metadata),
         do: {:ok, %{client_assertion: signing}}
  end

  defp authentication(_method, secrets),
    do:
      {:ok,
       %{
         client_secret: secrets["client_secret"],
         client_secret_expires_at: secrets["client_secret_expires_at"]
       }}
end
