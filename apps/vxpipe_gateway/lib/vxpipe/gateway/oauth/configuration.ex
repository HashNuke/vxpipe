defmodule Vxpipe.Gateway.OAuth.Configuration do
  @moduledoc "Trusted OAuth endpoint URLs and public discovery documents."

  def build(options) do
    base = %{
      enabled: Keyword.get(options, :enabled, false),
      allowed_hosts: Keyword.get(options, :allowed_hosts, []),
      allowed_origins: Keyword.get(options, :allowed_origins, []),
      allow_loopback_http: Keyword.get(options, :allow_loopback_http, false),
      backend: Keyword.get(options, :backend, Vxpipe.Identity.OAuth),
      client_address_resolver: Keyword.get(options, :client_address_resolver),
      routes: %{}
    }

    if base.enabled do
      issuer = url!(Keyword.get(options, :issuer), base.allow_loopback_http)
      resource = url!(Keyword.get(options, :resource), base.allow_loopback_http)
      issuer_url = URI.to_string(issuer) |> String.trim_trailing("/")
      resource_url = URI.to_string(resource)
      issuer_path = String.trim_trailing(issuer.path || "", "/")
      resource_path = resource.path || ""

      Map.merge(base, %{
        issuer: issuer_url,
        resource: resource_url,
        routes: %{
          ("/.well-known/oauth-authorization-server" <> issuer_path) => :server_metadata,
          ("/.well-known/oauth-protected-resource" <> resource_path) => :resource_metadata,
          (issuer_path <> "/oauth/register") => :register,
          (issuer_path <> "/oauth/token") => :token,
          (issuer_path <> "/oauth/revoke") => :revoke
        }
      })
    else
      base
    end
  end

  def metadata(:resource_metadata, options),
    do: %{
      resource: options.resource,
      authorization_servers: [options.issuer],
      scopes_supported: ["mcp"],
      bearer_methods_supported: ["header"]
    }

  def metadata(:server_metadata, options),
    do: %{
      issuer: options.issuer,
      authorization_endpoint: options.issuer <> "/oauth/authorize",
      token_endpoint: options.issuer <> "/oauth/token",
      registration_endpoint: options.issuer <> "/oauth/register",
      revocation_endpoint: options.issuer <> "/oauth/revoke",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      scopes_supported: ["mcp"]
    }

  defp url!(value, loopback?) when is_binary(value) do
    with {:ok, uri} <- URI.new(value),
         true <- is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment),
         true <- uri.port in 1..65_535,
         true <-
           uri.scheme == "https" or
             (loopback? and uri.scheme == "http" and uri.host in ["localhost", "127.0.0.1", "::1"]),
         true <- clean_path?(uri.path),
         false <- String.contains?(value, ["\\", " ", "\r", "\n", "\t"]) do
      uri
    else
      _invalid -> raise ArgumentError, "invalid OAuth endpoint URL"
    end
  end

  defp url!(_value, _loopback?), do: raise(ArgumentError, "invalid OAuth endpoint URL")
  defp clean_path?(path) when path in [nil, "", "/"], do: true

  defp clean_path?("/" <> path),
    do:
      Enum.all?(
        String.split(path, "/"),
        &(&1 not in ["", ".", ".."] and not String.contains?(&1, "%"))
      )

  defp clean_path?(_path), do: false
end
