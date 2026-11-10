# Run outside Mix: elixir docs/experiments/boruta-probe.exs
# Installs the pinned library in the normal Mix.install cache.
# In-memory, single-process experiment only. This is not production persistence.
Mix.install([{:boruta, "== 2.3.8"}])

defmodule BorutaFitProbe do
  alias Boruta.Oauth.{Client, ResourceOwner, Scope, Token}

  def run do
    Application.put_env(:boruta, Boruta.Oauth,
      contexts: [
        clients: __MODULE__,
        codes: __MODULE__,
        access_tokens: __MODULE__,
        scopes: __MODULE__,
        resource_owners: __MODULE__
      ]
    )

    client = %Client{
      id: "11111111-1111-4111-8111-111111111111",
      confidential: false,
      pkce: true,
      public_refresh_token: true,
      authorize_scope: false,
      redirect_uris: ["http://127.0.0.1:12345/callback"],
      supported_grant_types: ["authorization_code", "refresh_token"],
      access_token_ttl: 300,
      authorization_code_ttl: 60,
      refresh_token_ttl: 3600
    }

    Process.put(:client, client)
    owner = %ResourceOwner{sub: "synthetic-user", extra_claims: %{"grant_id" => "grant-1"}}
    Process.put(:owner, owner)
    verifier = String.duplicate("a", 43)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    params = %{
      "response_type" => "code",
      "client_id" => client.id,
      "redirect_uri" => hd(client.redirect_uris),
      "scope" => "mcp",
      "state" => "synthetic-state",
      "code_challenge" => challenge,
      "code_challenge_method" => "S256",
      "resource" => "https://example.com/mcp"
    }

    conn =
      Plug.Test.conn(:get, "/authorize?" <> URI.encode_query(params))
      |> Plug.Conn.fetch_query_params()

    {:ok, request} = Boruta.Oauth.Request.authorize_request(conn, owner)
    false = Map.has_key?(request, :resource)
    {:ok, response} = Boruta.Oauth.authorize(conn, owner, __MODULE__)
    %{"grant_id" => "grant-1"} = Process.get(:code_params).resource_owner.extra_claims
    IO.puts("PASS: S256 authorization and custom Codes.create; grant metadata reaches adapter")
    IO.puts("PASS: resource parameter absent from parsed authorize request")

    token_params = %{
      "grant_type" => "authorization_code",
      "client_id" => client.id,
      "redirect_uri" => hd(client.redirect_uris),
      "code" => response.code,
      "code_verifier" => String.duplicate("b", 43),
      "resource" => "https://wrong.example/mcp"
    }

    {:error, %{error: :invalid_request}} = token(token_params)
    nil = Process.get(:created_token)
    IO.puts("PASS: wrong verifier rejected before access-token creation")

    {:ok, access} = token(Map.put(token_params, "code_verifier", verifier))
    true = is_binary(access.access_token)
    response_code = response.code
    %{previous_code: ^response_code} = Process.get(:access_params)
    IO.puts("PASS: correct verifier accepted; custom AccessTokens.create receives previous_code")
    IO.puts("PASS: wrong resource does not prevent exchange inside Boruta (wrapper required)")
    {:error, %{error: :invalid_grant}} = token(Map.put(token_params, "code_verifier", verifier))
    IO.puts("PASS: sequential authorization-code reuse rejected")

    {:ok, refreshed} =
      token(%{
        "grant_type" => "refresh_token",
        "client_id" => client.id,
        "refresh_token" => access.refresh_token,
        "scope" => "mcp"
      })

    true = refreshed.access_token != access.access_token
    previous_access = access.access_token
    %{previous_token: ^previous_access} = Process.get(:access_params)

    {:error, %{error: :invalid_grant}} =
      token(%{
        "grant_type" => "refresh_token",
        "client_id" => client.id,
        "refresh_token" => access.refresh_token,
        "scope" => "mcp"
      })

    IO.puts(
      "PASS: public refresh rotates tokens through custom adapter; sequential reuse rejected"
    )

    IO.puts(
      "LIMIT: no database, concurrency, consent UI, discovery, or MCP resource enforcement tested"
    )
  end

  defp token(params) do
    conn = Plug.Test.conn(:post, "/token", params)
    Boruta.Oauth.token(conn, __MODULE__)
  end

  def get_client(id) do
    client = Process.get(:client)
    if client.id == id, do: client
  end

  def authorized_scopes(_), do: [%Scope{name: "mcp"}]
  def public, do: []
  def get_by(sub: "synthetic-user"), do: {:ok, Process.get(:owner)}

  def get_by(value: value, redirect_uri: redirect_uri) do
    case Process.get({:code, value}) do
      %Token{redirect_uri: ^redirect_uri} = token -> token
      _ -> nil
    end
  end

  def get_by(refresh_token: value), do: Process.get({:refresh, value})
  def get_by(value: value), do: Process.get({:access, value})

  def create(params) do
    Process.put(:code_params, params)

    token = %Token{
      type: "code",
      value: random(),
      expires_at: System.system_time(:second) + 60,
      client: params.client,
      resource_owner: params.resource_owner,
      sub: params.sub,
      scope: params.scope,
      state: params.state,
      redirect_uri: params.redirect_uri,
      code_challenge_hash: Token.hash(params.code_challenge),
      code_challenge_method: params.code_challenge_method
    }

    Process.put({:code, token.value}, token)
    {:ok, token}
  end

  def create(params, refresh_token: true) do
    Process.put(:access_params, params)

    token = %Token{
      type: "access_token",
      value: random(),
      refresh_token: random(),
      client: params.client,
      sub: params.sub,
      scope: params.scope,
      inserted_at: DateTime.utc_now(),
      expires_at: System.system_time(:second) + 300
    }

    Process.put(:created_token, token)
    Process.put({:access, token.value}, token)
    Process.put({:refresh, token.refresh_token}, token)
    {:ok, token}
  end

  def revoke(%Token{type: "code"} = token) do
    token = %{token | revoked_at: DateTime.utc_now()}
    Process.put({:code, token.value}, token)
    {:ok, token}
  end

  def revoke_refresh_token(token) do
    token = %{token | refresh_token_revoked_at: DateTime.utc_now()}
    Process.put({:access, token.value}, token)
    Process.put({:refresh, token.refresh_token}, token)
    {:ok, token}
  end

  def authorize_success(_, response), do: {:ok, response}
  def authorize_error(_, error), do: {:error, error}
  def token_success(_, response), do: {:ok, response}
  def token_error(_, error), do: {:error, error}
  defp random, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end

BorutaFitProbe.run()
