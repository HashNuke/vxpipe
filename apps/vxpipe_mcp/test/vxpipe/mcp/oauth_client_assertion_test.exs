defmodule Vxpipe.MCP.OAuthClientAssertionTest do
  use ExUnit.Case, async: true
  alias ExMCP.Authorization.JWT
  alias Vxpipe.MCP.OAuthClientAssertion

  setup_all do
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    weak = :public_key.generate_key({:rsa, 1024, 65_537})
    ec = :public_key.generate_key({:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}})
    wrong_curve = :public_key.generate_key({:namedCurve, {1, 3, 132, 0, 34}})
    public = pem(:RSAPublicKey, {:RSAPublicKey, elem(rsa, 2), elem(rsa, 3)})

    %{
      rsa: pem(:RSAPrivateKey, rsa),
      weak: pem(:RSAPrivateKey, weak),
      ec: pem(:ECPrivateKey, ec),
      public: public,
      wrong_curve: pem(:ECPrivateKey, wrong_curve)
    }
  end

  test "supported algorithms issue fresh, short-lived, client/token-bound assertions", data do
    for {algorithm, key} <- [{"RS256", data.rsa}, {"PS256", data.rsa}, {"ES256", data.ec}] do
      input = input(key, algorithm)
      assert {:ok, configured} = OAuthClientAssertion.new(input, metadata())
      refute inspect(configured) =~ "PRIVATE KEY"
      {:ok, private_key} = JWT.load_key(key)
      refute inspect(configured) =~ JWT.to_map(private_key)["d"]
      public_key = JWT.to_public_key(private_key)

      assertions =
        for _ <- 1..2 do
          before = System.os_time(:second)
          assert {:ok, pairs} = OAuthClientAssertion.parameters(configured)
          params = Map.new(pairs)

          assert Enum.sort(Map.keys(params)) ==
                   ~w(client_assertion client_assertion_type client_id)

          assert params["client_assertion_type"] ==
                   "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

          assert params["client_id"] == input.client_id

          assert {:ok, claims} =
                   JWT.verify_and_validate(params["client_assertion"], public_key,
                     iss: input.client_id,
                     sub: input.client_id,
                     aud: input.token_endpoint,
                     required: ~w(iss sub aud exp iat jti)
                   )

          assert claims["iat"] >= before
          assert claims["iat"] <= System.os_time(:second)
          assert claims["exp"] - claims["iat"] == 60
          assert Map.keys(claims) |> Enum.sort() == ~w(aud exp iat iss jti sub)
          [header | _] = String.split(params["client_assertion"], ".")
          header = header |> Base.url_decode64!(padding: false) |> JSON.decode!()
          assert header == %{"alg" => algorithm, "typ" => "JWT", "kid" => "registered-key"}
          claims["jti"]
        end

      assert length(Enum.uniq(assertions)) == 2
    end
  end

  test "rejects unsupported methods/algorithms and unbound destinations", data do
    input = input(data.rsa, "RS256")

    for {request, server} <- [
          {input, Map.delete(metadata(), "token_endpoint_auth_signing_alg_values_supported")},
          {input,
           Map.put(metadata(), "token_endpoint_auth_methods_supported", ["client_secret_basic"])},
          {input,
           Map.put(metadata(), "token_endpoint_auth_signing_alg_values_supported", ["ES256"])},
          {input,
           Map.put(metadata(), "token_endpoint_auth_signing_alg_values_supported", "RS256")},
          {Map.put(input, :algorithm, "none"), metadata()},
          {Map.put(input, :algorithm, "HS256"), metadata()},
          {Map.put(input, :token_endpoint, "https://other.example.test/token"), metadata()},
          {Map.put(input, :token_endpoint, "http://auth.example.test/token"),
           Map.put(metadata(), "token_endpoint", "http://auth.example.test/token")},
          {Map.put(input, :client_id, ""), metadata()},
          {Map.put(input, :key_id, "bad\nkey"), metadata()},
          {Map.put(input, :additional_claims, %{"aud" => "other"}), metadata()},
          {Map.put(input, :lifetime, 3600), metadata()}
        ] do
      assert {:error, :invalid_oauth_client_assertion} = OAuthClientAssertion.new(request, server)
    end
  end

  test "rejects weak, public, mismatched and non-PEM keys without disclosing input", data do
    {:ok, key} = JWT.load_key(data.rsa)
    public = key |> JWT.to_public_key() |> JWT.to_map()

    for value <- [
          data.weak,
          data.public,
          public,
          {:pem_file, "/unreadable/key"},
          "private-invalid-marker",
          String.duplicate("x", 16_385)
        ] do
      assert {:error, :invalid_oauth_client_assertion} =
               OAuthClientAssertion.new(input(value, "RS256"), metadata())
    end

    assert {:error, :invalid_oauth_client_assertion} =
             OAuthClientAssertion.new(input(data.ec, "RS256"), metadata())

    assert {:error, :invalid_oauth_client_assertion} =
             OAuthClientAssertion.new(input(data.rsa, "ES256"), metadata())

    assert {:error, :invalid_oauth_client_assertion} =
             OAuthClientAssertion.new(input(data.wrong_curve, "ES256"), metadata())
  end

  test "key ID is optional; replacement keys produce assertions for their own public keys",
       data do
    {:ok, rsa} = JWT.load_key(data.rsa)
    {:ok, ec} = JWT.load_key(data.ec)
    request = Map.delete(input(data.ec, "ES256"), :key_id)
    assert {:ok, configured} = OAuthClientAssertion.new(request, metadata())
    assert {:ok, pairs} = OAuthClientAssertion.parameters(configured)
    token = Map.new(pairs)["client_assertion"]
    assert {:ok, _} = JWT.verify(token, JWT.to_public_key(ec))
    assert {:error, _} = JWT.verify(token, JWT.to_public_key(rsa))
    [header | _] = String.split(token, ".")
    refute header |> Base.url_decode64!(padding: false) |> JSON.decode!() |> Map.has_key?("kid")
  end

  defp input(key, algorithm),
    do: %{
      client_id: "registered-client",
      token_endpoint: "https://auth.example.test/token",
      private_key: key,
      algorithm: algorithm,
      key_id: "registered-key"
    }

  defp metadata,
    do: %{
      "token_endpoint" => "https://auth.example.test/token",
      "token_endpoint_auth_methods_supported" => ["private_key_jwt"],
      "token_endpoint_auth_signing_alg_values_supported" => ["RS256", "PS256", "ES256"]
    }

  defp pem(type, key), do: :public_key.pem_encode([:public_key.pem_entry_encode(type, key)])
end
