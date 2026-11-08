defmodule Vxpipe.Calls.MachineOAuthRenewalTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.MCPOAuthProtocol, as: MCPOAuthRefresh
  alias Vxpipe.Calls.ResolvedMCPRefresh

  test "machine renewal uses the saved client grant, scope and metadata instead of a refresh token" do
    owner = self()

    secrets = %{
      "registration_method" => "own_client",
      "grant_type" => "client_credentials",
      "token_endpoint" => "https://auth.example.test/token",
      "client_id" => "registered",
      "auth_method" => "client_secret_post",
      "client_secret" => "private-secret",
      "resource" => "https://mcp.example.test/mcp",
      "scopes" => ["tools:read"],
      "issuer" => "https://auth.example.test",
      "token_parameters" => [%{"name" => "organization", "value" => "calendar"}],
      "machine_metadata" => %{
        "issuer" => "https://auth.example.test",
        "token_endpoint" => "https://auth.example.test/token",
        "grant_types_supported" => ["client_credentials"],
        "token_endpoint_auth_methods_supported" => ["client_secret_post"]
      }
    }

    claim = %ResolvedMCPRefresh{id: "claim", grant_revision: 1, secrets: secrets}

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn _, {_url, _headers, _type, body}, _, _ ->
        send(owner, {:request, URI.decode_query(body)})

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "new-machine-access",
            "refresh_token" => "unused",
            "token_type" => "Bearer",
            "expires_in" => 120
          })}}
      end
    ]

    assert {:ok, tokens} = MCPOAuthRefresh.refresh(options, claim)
    assert tokens["access_token"] == "new-machine-access"
    refute Map.has_key?(tokens, "refresh_token")
    refute Map.has_key?(tokens, "client_secret")
    assert_receive {:request, body}
    assert body["grant_type"] == "client_credentials"
    assert body["scope"] == "tools:read"
    assert body["resource"] == secrets["resource"]
    assert body["organization"] == "calendar"
    refute Map.has_key?(body, "refresh_token")
    refute Map.has_key?(body, "redirect_uri")

    for changed <- [
          Map.delete(secrets, "machine_metadata"),
          Map.put(secrets, "grant_type", "password"),
          Map.put(secrets, "registration_method", "dcr"),
          put_in(secrets, ["machine_metadata", "token_endpoint"], "https://other.test/token")
        ] do
      assert {:error, _} = MCPOAuthRefresh.refresh(options, %{claim | secrets: changed})
      refute_received {:request, _}
    end
  end
end
