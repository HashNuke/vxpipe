defmodule Vxpipe.MCP.OAuthSigningMetadataTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthMetadata
  @issuer "https://auth.example.test"
  @field "token_endpoint_auth_signing_alg_values_supported"

  test "discovery preserves advertised signing algorithms for Own-client validation" do
    body = Map.put(metadata(), @field, ["RS256", "ES256", "PS256"])
    assert {:ok, found} = discover(body)
    assert found[@field] == body[@field]
  end

  test "JWT methods require bounded algorithm metadata and never invent defaults" do
    for method <- ["private_key_jwt", "client_secret_jwt"] do
      body = Map.put(metadata(), "token_endpoint_auth_methods_supported", [method])
      assert {:error, :invalid_oauth_metadata} = discover(body)

      for algorithms <- [[], "RS256", [nil], ["bad\nalgorithm"], List.duplicate("RS256", 33)] do
        assert {:error, :invalid_oauth_metadata} = discover(Map.put(body, @field, algorithms))
      end
    end

    assert {:ok, _} =
             discover(
               Map.put(metadata(), "token_endpoint_auth_methods_supported", [
                 "client_secret_basic"
               ])
             )
  end

  defp metadata,
    do: %{
      "issuer" => @issuer,
      "authorization_endpoint" => @issuer <> "/authorize",
      "token_endpoint" => @issuer <> "/token",
      "token_endpoint_auth_methods_supported" => ["private_key_jwt"]
    }

  defp discover(body),
    do:
      OAuthMetadata.discover(@issuer,
        dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
        http_client: fn _, _, _ ->
          {:ok, %{status: 200, headers: [], body: JSON.encode!(body)}}
        end
      )
end
