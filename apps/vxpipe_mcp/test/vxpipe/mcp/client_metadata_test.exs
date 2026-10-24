defmodule Vxpipe.MCP.ClientMetadataTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.ClientMetadata

  test "CIMD identity and redirect URI come from the canonical installation origin" do
    assert {:ok, metadata} = ClientMetadata.document("https://calls.example.test:8443")
    assert metadata.client_id == "https://calls.example.test:8443/oauth/client-metadata.json"
    assert metadata.client_name == "VxPipe"
    assert metadata.redirect_uris == ["https://calls.example.test:8443/oauth/mcp/callback"]
    assert metadata.token_endpoint_auth_method == "none"
    assert metadata.grant_types == ["authorization_code", "refresh_token"]
    assert {:ok, registration} = ClientMetadata.registration("https://calls.example.test:8443")
    assert registration == Map.delete(metadata, :client_id)
  end

  test "CIMD never advertises an insecure, unconfigured or non-origin client identity" do
    for invalid <- [nil, "http://localhost:4000", "https://user:secret@example.test", "https://example.test/page", "https://example.test?x=1"] do
      assert {:error, :invalid_public_url} = ClientMetadata.document(invalid)
    end
  end
end
