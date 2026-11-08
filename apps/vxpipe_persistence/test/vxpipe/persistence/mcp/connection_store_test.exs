defmodule Vxpipe.Persistence.MCP.ConnectionStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Persistence.Schema.MCPConnection

  setup do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, other, _} =
      Administration.bootstrap_tenant("Other tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("old", %{"old" => :crypto.strong_rand_bytes(32)})

    attributes = %{
      endpoint: "https://mcp.example.test/mcp",
      endpoint_identity: "https://mcp.example.test/mcp",
      directory_id: "calendar",
      server_name: "Calendar",
      auth_method: "bearer",
      catalog: [%{"name" => "list_events", "inputSchema" => %{"type" => "object"}}]
    }

    %{
      tenant: tenant.key,
      other: other.key,
      context: [repo: Repo, keyring: keyring],
      attributes: attributes
    }
  end

  test "stores encrypted tenant-only credentials with stable connection identity", data do
    assert {:ok, connection} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{
               "token" => "synthetic-token"
             })

    assert connection.generation == 1
    assert connection.status == "connected"
    assert connection.tenant_key == data.tenant
    refute Map.has_key?(connection, :secrets)
    refute inspect(connection) =~ "synthetic-token"
    stored = Repo.get_by!(MCPConnection, public_id: connection.id)
    refute String.contains?(stored.encrypted_payload, "synthetic-token")
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, connection.id)
    assert resolved.secrets == %{"token" => "synthetic-token"}
    refute inspect(resolved) =~ "synthetic-token"
    assert {:ok, []} = ConnectionStore.list(data.context, data.other)

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.resolve(data.context, data.other, connection.id)

    assert {:error, :invalid_tenant_key} =
             ConnectionStore.create(data.context, :platform, data.attributes, %{})
  end

  test "the database rejects connected rows without ciphertext even when a key ID remains",
       data do
    {:ok, connection} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "fixture"})

    record = Repo.get_by!(MCPConnection, public_id: connection.id)

    assert {:error,
            %Postgrex.Error{postgres: %{code: :check_violation, constraint: "mcp_secret_state"}}} =
             Ecto.Adapters.SQL.query(
               Repo,
               "UPDATE tenant_mcp_connections SET encrypted_payload = NULL WHERE id = $1",
               [record.id],
               log: false
             )
  end

  test "accepted directory configuration survives management and retained-ID reconnection",
       data do
    listing = %{
      "directory_id" => "public-directory",
      "integration_id" => "calendar",
      "revision" => 2,
      "name" => "Directory Calendar",
      "endpoint" => data.attributes.endpoint,
      "authentication" => %{"type" => "bearer"},
      "setup_notes" => "Create a key in your account."
    }

    attributes =
      data.attributes
      |> Map.put(:directory_id, "public-directory/calendar")
      |> Map.put(:directory_entry, listing)

    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, attributes, %{"token" => "first"})

    assert original.directory_entry == listing
    assert original.server_name == "Directory Calendar"

    assert {:ok, refreshed} =
             ConnectionStore.refresh_catalog(
               data.context,
               data.tenant,
               original.id,
               1,
               Map.take(original, [:refreshed_at, :refresh_scheduled_at]),
               %{
                 server_name: "Protocol-reported name",
                 catalog: []
               }
             )

    assert refreshed.directory_entry == listing
    assert refreshed.server_name == "Directory Calendar"

    assert {:ok, replaced} =
             ConnectionStore.replace(data.context, data.tenant, original.id, 1, attributes, %{
               "token" => "replacement"
             })

    assert replaced.directory_entry == listing
    assert replaced.id == original.id
    assert replaced.generation == 2

    assert {:ok, revoked} =
             ConnectionStore.revoke(data.context, data.tenant, original.id, replaced.generation)

    assert revoked.directory_entry == listing
    assert revoked.directory_id == "public-directory/calendar"

    assert {:ok, ^revoked} =
             ConnectionStore.get_retained(
               Keyword.put(data.context, :keyring, nil),
               data.tenant,
               original.id
             )

    assert {:ok, restored} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               original.id,
               revoked.generation,
               attributes,
               %{"token" => "fresh"}
             )

    assert restored.directory_entry == listing
    assert restored.namespace == original.namespace
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, original.id)
    assert resolved.connection.directory_entry == listing
    assert resolved.secrets == %{"token" => "fresh"}
    assert {:ok, [^restored]} = ConnectionStore.list(data.context, data.tenant)
    assert {:ok, ^restored} = ConnectionStore.get(data.context, data.tenant, original.id)
  end

  test "an unavailable repository fails safely and recovery preserves the saved connection",
       data do
    {:ok, connection} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{
        "token" => "before-outage"
      })

    previous = Repo.get_dynamic_repo()
    name = Vxpipe.Persistence.MCPConnectionRestartRepo
    repository = start_supervised!({Repo, name: name, pool_size: 1})
    monitor = Process.monitor(repository)
    stop_supervised!(Repo)
    assert_receive {:DOWN, ^monitor, :process, ^repository, :shutdown}

    try do
      for unavailable <- [name, repository] do
        Repo.put_dynamic_repo(unavailable)

        assert {:error, :mcp_connections_unavailable} =
                 ConnectionStore.create(data.context, data.other, data.attributes, %{
                   "token" => "during-outage"
                 })

        assert {:error, :mcp_connections_unavailable} =
                 ConnectionStore.list(data.context, data.tenant)

        assert {:error, :mcp_connections_unavailable} =
                 ConnectionStore.resolve(data.context, data.tenant, connection.id)
      end
    after
      Repo.put_dynamic_repo(previous)
    end

    assert {:ok, [^connection]} = ConnectionStore.list(data.context, data.tenant)
    assert {:ok, []} = ConnectionStore.list(data.context, data.other)
    assert {:ok, restored} = ConnectionStore.resolve(data.context, data.tenant, connection.id)
    assert restored.secrets == %{"token" => "before-outage"}
  end

  test "listed records reject private snapshot fields and inconsistent accepted identities",
       data do
    entry = directory_entry(data.attributes.endpoint)

    attributes =
      data.attributes
      |> Map.put(:directory_id, "public-directory/calendar")
      |> Map.put(:directory_entry, entry)

    for invalid <- [
          Map.put(attributes, :directory_id, "another-directory/calendar"),
          Map.put(attributes, :endpoint, "https://different.example.test/mcp"),
          Map.put(attributes, :endpoint_identity, "https://different.example.test/mcp"),
          Map.put(attributes, :auth_method, "none"),
          put_in(attributes, [:directory_entry, "client_secret"], "private-marker"),
          put_in(attributes, [:directory_entry, "authentication", "token"], "private-marker"),
          put_in(
            attributes,
            [:directory_entry, "setup_url"],
            "https://user:password@example.test"
          ),
          put_in(attributes, [:directory_entry, "revision"], 0)
        ] do
      assert {:error, :invalid_mcp_configuration} =
               ConnectionStore.create(data.context, data.tenant, invalid, %{"token" => "secret"})

      assert {:ok, []} = ConnectionStore.list(data.context, data.tenant)
    end
  end

  test "credential replacement cannot detach or rewrite an accepted directory configuration",
       data do
    attributes =
      data.attributes
      |> Map.put(:directory_id, "public-directory/calendar")
      |> Map.put(:directory_entry, directory_entry(data.attributes.endpoint))

    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, attributes, %{
               "token" => "original"
             })

    for changed <- [
          Map.put(attributes, :directory_entry, nil),
          Map.put(attributes, :directory_id, nil),
          put_in(attributes, [:directory_entry, "revision"], 3),
          put_in(attributes, [:directory_entry, "name"], "Changed name"),
          put_in(attributes, [:directory_entry, "setup_notes"], "Changed instructions")
        ] do
      assert {:error, :invalid_mcp_configuration} =
               ConnectionStore.replace(
                 data.context,
                 data.tenant,
                 original.id,
                 original.generation,
                 changed,
                 %{"token" => "replacement"}
               )

      assert {:ok, ^original} = ConnectionStore.get(data.context, data.tenant, original.id)
      assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, original.id)
      assert resolved.connection.generation == original.generation
      assert resolved.secrets == %{"token" => "original"}
    end
  end

  test "a maximum-length directory binding fits and omitted snapshots remain unchanged", data do
    directory = String.duplicate("d", 64)
    integration = String.duplicate("i", 64)
    identity = directory <> "/" <> integration

    entry =
      directory_entry(data.attributes.endpoint)
      |> Map.put("directory_id", directory)
      |> Map.put("integration_id", integration)

    attributes =
      data.attributes
      |> Map.put(:directory_id, identity)
      |> Map.put(:directory_entry, entry)

    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, attributes, %{"token" => "old"})

    assert original.directory_id == identity
    assert original.directory_entry == entry

    replacement =
      attributes
      |> Map.delete(:directory_entry)
      |> Map.put(:server_name, "New protocol-reported name")

    assert {:ok, replaced} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               original.id,
               original.generation,
               replacement,
               %{"token" => "fresh"}
             )

    assert replaced.directory_entry == entry
    assert replaced.server_name == entry["name"]
    assert replaced.directory_id == identity
    assert replaced.generation == original.generation + 1
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, original.id)
    assert resolved.secrets == %{"token" => "fresh"}
  end

  test "restoring a revoked identity requires fresh secrets and advances its generation", data do
    {:ok, original} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "old"})

    {:ok, revoked} =
      ConnectionStore.revoke(data.context, data.tenant, original.id, original.generation)

    assert {:error, :mcp_connection_revoked} =
             ConnectionStore.resolve(data.context, data.tenant, original.id)

    assert {:error, :stale_mcp_connection} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               original.id,
               original.generation,
               data.attributes,
               %{"token" => "stale"}
             )

    assert {:ok, restored} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               original.id,
               revoked.generation,
               data.attributes,
               %{"token" => "fresh"}
             )

    assert restored.id == original.id
    assert restored.namespace == original.namespace
    assert restored.generation == revoked.generation + 1
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, original.id)
    assert resolved.secrets == %{"token" => "fresh"}
  end

  test "retained metadata lookup needs no decryption and includes revoked identities only in its tenant",
       data do
    attributes = Map.put(data.attributes, :auth_method, "oauth")

    {:ok, original} =
      ConnectionStore.create(data.context, data.tenant, attributes, %{"access_token" => "old"})

    no_keys = Keyword.put(data.context, :keyring, nil)
    assert {:ok, ^original} = ConnectionStore.get_retained(no_keys, data.tenant, original.id)

    {:ok, revoked} =
      ConnectionStore.revoke(data.context, data.tenant, original.id, original.generation)

    assert {:ok, ^revoked} = ConnectionStore.get_retained(no_keys, data.tenant, original.id)

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.get_retained(no_keys, data.other, original.id)

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.get(no_keys, data.tenant, original.id)

    assert {:ok, []} = ConnectionStore.list(no_keys, data.tenant)
    refute Map.has_key?(revoked, :secrets)
  end

  test "OAuth completion preserves attempt connection identity and encrypts grant material",
       data do
    id = Ecto.UUID.generate()
    attributes = %{data.attributes | auth_method: "oauth"}

    secrets = %{
      "access_token" => "private-access",
      "refresh_token" => "private-refresh",
      "client_secret" => "private-client-secret",
      "client_secret_expires_at" => 2_000_000_000
    }

    assert {:ok, connection} =
             ConnectionStore.create_oauth(data.context, data.tenant, id, attributes, secrets)

    assert connection.id == id
    assert connection.auth_method == "oauth"
    refute Map.has_key?(connection, :client_secret_expires_at)
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, id)
    assert resolved.secrets == secrets
    stored = Repo.get_by!(MCPConnection, public_id: id)
    refute stored.encrypted_payload =~ "private-access"

    assert {:error, _} =
             ConnectionStore.create_oauth(data.context, data.tenant, id, attributes, secrets)

    assert {:error, :invalid_oauth_connection} =
             ConnectionStore.create_oauth(data.context, data.other, "bad-id", attributes, secrets)
  end

  test "public details need no decryption key and enforce tenant identity", data do
    {:ok, connection} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "hidden"})

    context = Keyword.delete(data.context, :keyring)
    assert {:ok, details} = ConnectionStore.get(context, data.tenant, connection.id)
    assert details.catalog == data.attributes.catalog
    refute inspect(details) =~ "hidden"

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.get(context, data.other, connection.id)
  end

  test "directory and endpoint duplicates return the existing identity", data do
    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{})

    assert {:error, {:mcp_connection_exists, id}} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{})

    assert id == original.id
    custom = %{data.attributes | directory_id: nil}

    assert {:error, {:mcp_connection_exists, ^id}} =
             ConnectionStore.create(data.context, data.tenant, custom, %{})

    assert {:ok, _} = ConnectionStore.create(data.context, data.other, data.attributes, %{})
  end

  test "identity lookup is tenant-scoped metadata and includes revoked records without keys",
       data do
    identity = Map.take(data.attributes, [:endpoint_identity, :directory_id])
    no_keys = Keyword.put(data.context, :keyring, nil)
    assert {:ok, nil} = ConnectionStore.find_identity(no_keys, data.tenant, identity)

    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{
               "token" => "private"
             })

    assert {:ok, ^original} = ConnectionStore.find_identity(no_keys, data.tenant, identity)
    assert {:ok, nil} = ConnectionStore.find_identity(no_keys, data.other, identity)

    assert {:ok, ^original} =
             ConnectionStore.find_identity(no_keys, data.tenant, %{identity | directory_id: nil})

    assert {:ok, revoked} = ConnectionStore.revoke(data.context, data.tenant, original.id, 1)
    assert {:ok, ^revoked} = ConnectionStore.find_identity(no_keys, data.tenant, identity)
    refute inspect(revoked) =~ "private"

    assert {:error, :invalid_tenant_key} =
             ConnectionStore.find_identity(no_keys, :platform, identity)
  end

  test "identity lookup selects the same deterministic endpoint-or-directory match as create",
       data do
    assert {:ok, first} = ConnectionStore.create(data.context, data.tenant, data.attributes, %{})

    second_attributes = %{
      data.attributes
      | endpoint: "https://second.example.test/mcp",
        endpoint_identity: "https://second.example.test/mcp",
        directory_id: "other-directory"
    }

    assert {:ok, second} =
             ConnectionStore.create(data.context, data.tenant, second_attributes, %{})

    competing = %{second_attributes | directory_id: data.attributes.directory_id}
    identity = Map.take(competing, [:endpoint_identity, :directory_id])
    no_keys = Keyword.put(data.context, :keyring, nil)
    assert {:ok, ^first} = ConnectionStore.find_identity(no_keys, data.tenant, identity)

    assert {:error, {:mcp_connection_exists, id}} =
             ConnectionStore.create(data.context, data.tenant, competing, %{})

    assert id == first.id

    assert {:ok, ^second} =
             ConnectionStore.find_identity(no_keys, data.tenant, %{identity | directory_id: nil})
  end

  test "OAuth details reveal only fixed method labels and remain readable without a key", data do
    secrets = %{
      "registration_method" => "own_client",
      "grant_type" => "authorization_code",
      "auth_method" => "private_key_jwt",
      "client_id" => "private-client",
      "private_key" => "private-signing-key",
      "access_token" => "private-token",
      "token_parameters" => [%{"name" => "organization", "value" => "private-org"}]
    }

    assert {:ok, connection} =
             ConnectionStore.create(
               data.context,
               data.tenant,
               %{data.attributes | auth_method: "oauth"},
               secrets
             )

    assert {:ok, details} = ConnectionStore.get(data.context, data.tenant, connection.id)

    assert details.oauth == %{
             "registration_method" => "own_client",
             "grant_type" => "authorization_code",
             "auth_method" => "private_key_jwt"
           }

    refute JSON.encode!(details) =~ "private-"

    assert {:ok, without_key} =
             ConnectionStore.get(
               Keyword.delete(data.context, :keyring),
               data.tenant,
               connection.id
             )

    assert without_key.catalog == details.catalog
    assert Map.get(without_key, :oauth) == nil
  end

  test "catalog refresh preserves encrypted grants and configuration generation", data do
    {:ok, connection} =
      ConnectionStore.create(
        data.context,
        data.tenant,
        %{data.attributes | auth_method: "oauth"},
        %{"access_token" => "old", "refresh_token" => "refresh"}
      )

    encrypted = Repo.get_by!(MCPConnection, public_id: connection.id).encrypted_payload
    context = Keyword.delete(data.context, :keyring)

    attributes = %{
      server_name: "Renamed calendar",
      catalog: [%{"name" => "new_tool", "inputSchema" => %{"type" => "object"}}]
    }

    assert {:ok, refreshed} =
             ConnectionStore.refresh_catalog(
               context,
               data.tenant,
               connection.id,
               1,
               Map.take(connection, [:refreshed_at, :refresh_scheduled_at]),
               attributes
             )

    assert refreshed.catalog == attributes.catalog
    assert refreshed.server_name == attributes.server_name
    assert refreshed.generation == 1
    assert refreshed.auth_method == "oauth"
    assert Repo.get_by!(MCPConnection, public_id: connection.id).encrypted_payload == encrypted
    assert {:ok, saved} = ConnectionStore.resolve(data.context, data.tenant, connection.id)
    assert saved.secrets["refresh_token"] == "refresh"

    assert {:error, :invalid_mcp_configuration} =
             ConnectionStore.refresh_catalog(
               context,
               data.tenant,
               connection.id,
               1,
               Map.take(refreshed, [:refreshed_at, :refresh_scheduled_at]),
               Map.put(attributes, :auth_method, "none")
             )

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.refresh_catalog(
               context,
               data.other,
               connection.id,
               1,
               Map.take(refreshed, [:refreshed_at, :refresh_scheduled_at]),
               attributes
             )

    assert {:ok, _} = ConnectionStore.revoke(context, data.tenant, connection.id, 1)

    assert {:error, :stale_mcp_connection} =
             ConnectionStore.refresh_catalog(
               context,
               data.tenant,
               connection.id,
               1,
               Map.take(refreshed, [:refreshed_at, :refresh_scheduled_at]),
               attributes
             )

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.refresh_catalog(
               context,
               data.tenant,
               connection.id,
               2,
               Map.take(refreshed, [:refreshed_at, :refresh_scheduled_at]),
               attributes
             )
  end

  test "replacement and revocation reject stale generations and never expose old secrets", data do
    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{
               "token" => "old"
             })

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.replace(data.context, data.other, original.id, 1, data.attributes, %{
               "token" => "foreign"
             })

    assert {:ok, unchanged} = ConnectionStore.resolve(data.context, data.tenant, original.id)
    assert unchanged.secrets == %{"token" => "old"}

    assert {:ok, updated} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               original.id,
               1,
               data.attributes,
               %{"token" => "new"}
             )

    assert updated.id == original.id
    assert updated.generation == 2

    assert {:error, :stale_mcp_connection} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               original.id,
               1,
               data.attributes,
               %{"token" => "stale"}
             )

    assert {:error, :mcp_connection_not_found} =
             ConnectionStore.revoke(data.context, data.other, original.id, 2)

    assert {:ok, revoked} = ConnectionStore.revoke(data.context, data.tenant, original.id, 2)
    assert revoked.generation == 3

    assert {:error, :mcp_connection_revoked} =
             ConnectionStore.resolve(data.context, data.tenant, original.id)

    assert Repo.get_by!(MCPConnection, public_id: original.id).encrypted_payload == nil
  end

  test "key rotation updates ciphertext without changing the connection generation", data do
    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, data.attributes, %{
               "token" => "rotation-token"
             })

    old = Keyword.fetch!(data.context, :keyring)

    {:ok, keys} =
      CredentialKeyring.new("new", Map.put(old.keys, "new", :crypto.strong_rand_bytes(32)))

    context = Keyword.put(data.context, :keyring, keys)
    assert {:ok, %{processed: 1, remaining_by_key: %{}}} = ConnectionStore.reencrypt(context, 10)
    assert {:ok, result} = ConnectionStore.resolve(context, data.tenant, original.id)
    assert result.connection.generation == 1
    assert result.secrets == %{"token" => "rotation-token"}
    assert Repo.get_by!(MCPConnection, public_id: original.id).encryption_key_id == "new"
  end

  test "a failed re-encryption row rolls back earlier rows in its batch", data do
    {:ok, first} =
      ConnectionStore.create(data.context, data.tenant, data.attributes, %{"token" => "first"})

    other = %{
      data.attributes
      | endpoint: "https://other.example.test/mcp",
        endpoint_identity: "https://other.example.test/mcp",
        directory_id: "other"
    }

    {:ok, second} =
      ConnectionStore.create(data.context, data.tenant, other, %{"token" => "second"})

    first_record = Repo.get_by!(MCPConnection, public_id: first.id)
    second_record = Repo.get_by!(MCPConnection, public_id: second.id)
    <<_version, rest::binary>> = second_record.encrypted_payload

    Repo.update!(Ecto.Changeset.change(second_record, encrypted_payload: <<2, rest::binary>>),
      log: false
    )

    keys = Keyword.fetch!(data.context, :keyring)

    {:ok, rotated} =
      CredentialKeyring.new("new", Map.put(keys.keys, "new", :crypto.strong_rand_bytes(32)))

    assert {:error, :mcp_secret_unreadable} =
             ConnectionStore.reencrypt(Keyword.put(data.context, :keyring, rotated), 2)

    unchanged = Repo.get_by!(MCPConnection, public_id: first.id)
    assert unchanged.encryption_key_id == first_record.encryption_key_id
    assert unchanged.encrypted_payload == first_record.encrypted_payload
  end

  test "programmer errors remain errors instead of repository outage results", data do
    assert_raise KeyError, fn ->
      ConnectionStore.list(Keyword.delete(data.context, :repo), data.tenant)
    end
  end

  test "callers cannot choose the initial generation or persist a failed replacement", data do
    attributes = Map.put(data.attributes, :generation, 99)

    assert {:ok, original} =
             ConnectionStore.create(data.context, data.tenant, attributes, %{
               "token" => "original"
             })

    assert original.generation == 1
    invalid = %{data.attributes | server_name: ""}

    assert {:error, :invalid_mcp_connection} =
             ConnectionStore.replace(data.context, data.tenant, original.id, 1, invalid, %{
               "token" => "replacement"
             })

    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, original.id)
    assert resolved.connection.generation == 1
    assert resolved.secrets == %{"token" => "original"}
  end

  test "conflicting endpoint and directory identities return a duplicate without crashing",
       data do
    assert {:ok, first} = ConnectionStore.create(data.context, data.tenant, data.attributes, %{})

    second_attributes = %{
      data.attributes
      | endpoint: "https://second.example.test/mcp",
        endpoint_identity: "https://second.example.test/mcp",
        directory_id: "second"
    }

    assert {:ok, _second} =
             ConnectionStore.create(data.context, data.tenant, second_attributes, %{})

    conflict = %{second_attributes | directory_id: "calendar"}

    assert {:error, {:mcp_connection_exists, id}} =
             ConnectionStore.create(data.context, data.tenant, conflict, %{})

    assert id == first.id
  end

  defp directory_entry(endpoint) do
    %{
      "directory_id" => "public-directory",
      "integration_id" => "calendar",
      "revision" => 2,
      "name" => "Directory Calendar",
      "endpoint" => endpoint,
      "authentication" => %{"type" => "bearer"}
    }
  end
end
