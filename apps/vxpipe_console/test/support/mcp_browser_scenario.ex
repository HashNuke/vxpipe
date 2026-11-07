defmodule Vxpipe.Console.Test.MCPBrowserScenario do
  @moduledoc "Startup-selected protocol scenarios with fresh local acceptance credentials."
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer
  alias Vxpipe.MCP.{Authentication, StaticConfiguration}

  def new(mode, options \\ [])

  def new(mode, _options) when mode in ~w(cimd dcr),
    do: {:ok, %{state: OutboundMCPOAuthServer.initial(mode), credentials: %{}}}

  def new(mode, _options) when mode in ~w(partial multiple_issuers unsupported) do
    settings =
      case mode do
        "partial" -> %{metadata_failures: 1}
        "multiple_issuers" -> %{multiple_issuers: true}
        "unsupported" -> %{unsupported_oauth: true}
      end

    state = Map.merge(OutboundMCPOAuthServer.initial("cimd"), settings)
    {:ok, %{state: state, credentials: %{}}}
  end

  def new("protected_dcr", _options) do
    token = secret()
    state = Map.put(OutboundMCPOAuthServer.initial("dcr"), :initial_access_token, token)
    {:ok, %{state: state, credentials: %{"initial_access_token" => token}}}
  end

  def new(mode, options) when mode in ~w(own_client machine) do
    method = Keyword.get(options, :client_auth_method, "client_secret_basic")
    supported = ~w(client_secret_basic client_secret_post private_key_jwt)
    supported = if mode == "own_client", do: ["none" | supported], else: supported

    if method in supported do
      own_client(mode, method)
    else
      {:error, :unsupported_browser_scenario}
    end
  end

  def new(mode, _options) when mode in ~w(none bearer headers basic) do
    credentials = credentials(mode)

    {:ok, configuration} =
      StaticConfiguration.new(%{
        "endpoint" => OutboundMCPOAuthServer.resource(),
        "auth_method" => mode,
        "credentials" => credentials
      })

    {:ok, headers} = Authentication.headers(configuration.authentication)
    state = Map.put(OutboundMCPOAuthServer.initial(mode), :static_headers, headers)
    {:ok, %{state: state, credentials: credentials}}
  end

  def new(_mode, _options), do: {:error, :unsupported_browser_scenario}

  defp own_client(mode, method) do
    grant = if mode == "machine", do: "client_credentials", else: "authorization_code"
    {credentials, registered} = client_credentials(method)
    client_id = "browser-client-" <> secret()

    credentials =
      Map.merge(credentials, %{
        "client_id" => client_id,
        "client_auth_method" => method,
        "grant_type" => grant
      })

    registered = Map.put(registered, "token_endpoint_auth_method", method)

    state =
      Map.merge(OutboundMCPOAuthServer.initial("own_client"), %{
        grant: grant,
        clients: %{client_id => registered}
      })

    {:ok, %{state: state, credentials: credentials}}
  end

  defp client_credentials("none"), do: {%{}, %{}}

  defp client_credentials("private_key_jwt") do
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa)])
    {:ok, key} = ExMCP.Authorization.JWT.load_key(pem)

    {%{"private_key" => pem, "algorithm" => "RS256", "key_id" => "browser-key"},
     %{"public_key" => ExMCP.Authorization.JWT.to_public_key(key)}}
  end

  defp client_credentials(_method) do
    credentials = %{"client_secret" => secret()}
    {credentials, credentials}
  end

  defp credentials("none"), do: %{}
  defp credentials("bearer"), do: %{"token" => secret()}
  defp credentials("basic"), do: %{"username" => "fixture-user", "password" => secret()}

  defp credentials("headers"),
    do: %{"headers" => [%{"name" => "x-api-key", "value" => secret()}]}

  defp secret, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
