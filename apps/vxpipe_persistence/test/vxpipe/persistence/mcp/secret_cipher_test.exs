defmodule Vxpipe.Persistence.MCP.SecretCipherTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.ProviderCredential
  alias Vxpipe.Persistence.{CredentialCipher, CredentialKeyring}
  alias Vxpipe.Persistence.MCP.SecretCipher

  setup do
    {:ok, keys} = CredentialKeyring.new("old", %{"old" => :crypto.strong_rand_bytes(32)})

    identity = %{
      tenant_key: "tenant-a",
      connection_id: "connection-a",
      generation: 1,
      auth_method: "bearer",
      purpose: "connection"
    }

    %{keys: keys, identity: identity}
  end

  test "secrets are bound to tenant, connection, generation, auth method and purpose", data do
    payload = %{"token" => "synthetic-private-token"}
    assert {:ok, key_id, encrypted} = SecretCipher.encrypt(data.keys, data.identity, payload)
    refute String.contains?(encrypted, "synthetic-private-token")
    assert {:ok, ^payload} = SecretCipher.decrypt(data.keys, data.identity, key_id, encrypted)

    for {field, value} <- [
          tenant_key: "tenant-b",
          connection_id: "connection-b",
          generation: 2,
          auth_method: "oauth",
          purpose: "grant"
        ] do
      assert {:error, :mcp_secret_unreadable} =
               SecretCipher.decrypt(
                 data.keys,
                 Map.put(data.identity, field, value),
                 key_id,
                 encrypted
               )
    end
  end

  test "rotation uses the shared keyring and preserves identity", data do
    payload = %{"token" => "synthetic-private-token"}
    assert {:ok, "old", encrypted} = SecretCipher.encrypt(data.keys, data.identity, payload)

    {:ok, rotated} =
      CredentialKeyring.new("new", Map.put(data.keys.keys, "new", :crypto.strong_rand_bytes(32)))

    assert {:ok, ^payload} = SecretCipher.decrypt(rotated, data.identity, "old", encrypted)
    assert {:ok, "new", replacement} = SecretCipher.encrypt(rotated, data.identity, payload)
    {:ok, retired} = CredentialKeyring.new("new", %{"new" => rotated.keys["new"]})
    assert {:ok, ^payload} = SecretCipher.decrypt(retired, data.identity, "new", replacement)

    assert {:error, :credential_key_unavailable} =
             SecretCipher.decrypt(retired, data.identity, "old", encrypted)
  end

  test "rejects platform ownership and malformed envelopes without exposing payload", data do
    assert {:error, :invalid_mcp_secret} =
             SecretCipher.encrypt(data.keys, %{data.identity | tenant_key: nil}, %{})

    assert {:error, :invalid_mcp_secret} =
             SecretCipher.encrypt(data.keys, data.identity, %{
               "token" => String.duplicate("x", 65_537)
             })

    assert {:error, :mcp_secret_unreadable} =
             SecretCipher.decrypt(data.keys, data.identity, "old", <<1, 2, 3>>)
  end

  test "key IDs remain bound even when two IDs contain the same key", data do
    key = Map.fetch!(data.keys.keys, "old")
    {:ok, aliases} = CredentialKeyring.new("old", %{"old" => key, "alias" => key})

    assert {:ok, "old", encrypted} =
             SecretCipher.encrypt(aliases, data.identity, %{"token" => "fixture"})

    assert {:error, :mcp_secret_unreadable} =
             SecretCipher.decrypt(aliases, data.identity, "alias", encrypted)
  end

  test "provider and MCP envelopes cannot be substituted across their storage namespaces", data do
    provider = %ProviderCredential{
      id: data.identity.connection_id,
      tenant_key: data.identity.tenant_key,
      provider: "fixture",
      name: "default",
      auth_kind: "bearer"
    }

    payload = %{"token" => "synthetic-token"}

    assert {:ok, "old", provider_envelope} =
             CredentialCipher.encrypt(data.keys, provider, payload)

    assert {:error, :mcp_secret_unreadable} =
             SecretCipher.decrypt(data.keys, data.identity, "old", provider_envelope)

    assert {:ok, "old", mcp_envelope} = SecretCipher.encrypt(data.keys, data.identity, payload)

    assert {:error, :provider_credential_unreadable} =
             CredentialCipher.decrypt(data.keys, provider, "old", mcp_envelope)
  end

  test "the payload limit accepts its exact boundary but rejects oversized and unsupported envelopes",
       data do
    overhead = byte_size(JSON.encode!(%{"token" => ""}))
    payload = %{"token" => String.duplicate("x", 65_536 - overhead)}
    assert byte_size(JSON.encode!(payload)) == 65_536

    assert {:ok, "old", <<1, envelope::binary>> = encrypted} =
             SecretCipher.encrypt(data.keys, data.identity, payload)

    assert {:ok, ^payload} = SecretCipher.decrypt(data.keys, data.identity, "old", encrypted)

    assert {:error, :mcp_secret_unreadable} =
             SecretCipher.decrypt(data.keys, data.identity, "old", encrypted <> <<0>>)

    assert {:error, :mcp_secret_unreadable} =
             SecretCipher.decrypt(nil, data.identity, "old", encrypted <> <<0>>)

    assert {:error, :mcp_secret_unreadable} =
             SecretCipher.decrypt(data.keys, data.identity, "old", <<2, envelope::binary>>)
  end

  test "encoding failures return only the fixed secret error", data do
    assert {:error, :invalid_mcp_secret} =
             SecretCipher.encrypt(data.keys, data.identity, %{"unsupported" => self()})
  end
end
