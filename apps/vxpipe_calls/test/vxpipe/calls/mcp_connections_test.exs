defmodule Vxpipe.Calls.MCPConnectionsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.MCPConnections
  alias Vxpipe.Identity.Principal
  alias Vxpipe.Calls.Test.{MCPProbeFixture, MCPRepositoryFixture}

  @tenant "AAAAAAAAAAAAAAAA"
  setup do
    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "auth_method" => "bearer",
      "credentials" => %{"token" => "synthetic"}
    }

    checked = %Vxpipe.Calls.ResolvedMCPConnection{
      connection: %{
        endpoint: input["endpoint"],
        endpoint_identity: input["endpoint"],
        auth_method: "bearer",
        server_name: "Calendar",
        catalog: [],
        directory_id: nil
      },
      secrets: input["credentials"]
    }

    options = [
      credential_repository: {MCPRepositoryFixture, self()},
      mcp_connection_repository: {MCPRepositoryFixture, self()},
      mcp_connection_probe: {MCPProbeFixture, {self(), {:ok, checked}}},
      refresh_authority: fn -> {:ok, principal} end
    ]

    %{principal: principal, input: input, checked: checked, options: options}
  end

  test "tenant write permission is checked before any probe or persistence", data do
    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}

    assert {:error, :forbidden} =
             MCPConnections.connect(reader, @tenant, data.input, data.options)

    assert {:error, :forbidden} =
             MCPConnections.connect(data.principal, "BBBBBBBBBBBBBBBB", data.input, data.options)

    assert {:error, :invalid_tenant_key} =
             MCPConnections.connect(data.principal, :platform, data.input, data.options)

    refute_received {:mcp_probe, _, _}
    refute_received {:mcp_create, _, _, _}
  end

  test "successful initialization/catalog check precedes save and only public metadata is returned",
       data do
    assert {:ok, result} =
             MCPConnections.connect(data.principal, @tenant, data.input, data.options)

    assert_receive {:mcp_probe, @tenant, _}
    assert_receive {:mcp_create, @tenant, attributes, %{"token" => "synthetic"}}
    assert attributes.server_name == "Calendar"
    refute Map.has_key?(result, :secrets)
    assert {:ok, [entry]} = MCPConnections.list(data.principal, @tenant, data.options)
    refute Map.has_key?(entry, :secrets)
  end

  test "failed probes and permissions revoked during discovery never write", data do
    options =
      Keyword.put(
        data.options,
        :mcp_connection_probe,
        {MCPProbeFixture, {self(), {:error, {:raw_provider_error, "secret"}}}}
      )

    assert {:error, :mcp_connection_failed} =
             MCPConnections.connect(data.principal, @tenant, data.input, options)

    revoked = %{data.principal | grants: MapSet.new()}
    options = Keyword.put(data.options, :refresh_authority, fn -> {:ok, revoked} end)

    assert {:error, :forbidden} =
             MCPConnections.connect(data.principal, @tenant, data.input, options)

    refute_received {:mcp_create, _, _, _}
  end

  test "listed creation preserves accepted identity after authorized checking", data do
    {entry, checked, options} = listed(data)

    input = %{
      "listing" => %{
        "directory_id" => entry["directory_id"],
        "integration_id" => entry["integration_id"],
        "entry_revision" => entry["revision"],
        "page" => %{}
      },
      "credentials" => %{"token" => "synthetic"}
    }

    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}
    assert {:error, :forbidden} = MCPConnections.connect(reader, @tenant, input, options)
    refute_received {:mcp_probe, _, _}
    assert {:ok, public} = MCPConnections.connect(data.principal, @tenant, input, options)
    assert public.directory_entry == entry
    assert public.directory_id == checked.connection.directory_id
    assert_receive {:mcp_probe, @tenant, ^input}
    assert_receive {:mcp_create, @tenant, %{directory_entry: ^entry}, %{"token" => "synthetic"}}
    refute inspect(public) =~ "synthetic"
  end

  test "listed replacements use only saved configuration and may retain saved credentials",
       data do
    {entry, checked, options} = listed(data)
    saved = Map.merge(checked.connection, %{generation: 3, status: "connected"})

    options =
      Keyword.put(options, :mcp_connection_repository, {MCPRepositoryFixture, {self(), saved}})

    input = %{
      "endpoint" => "https://attacker.example.test/mcp",
      "auth_method" => "none",
      "credentials" => %{"token" => "replacement"}
    }

    assert {:error, :stale_mcp_connection} =
             MCPConnections.update(data.principal, @tenant, "connection-id", 2, input, options)

    refute_received {:mcp_probe_saved, _, _, _}

    assert {:ok, public} =
             MCPConnections.update(data.principal, @tenant, "connection-id", 3, input, options)

    assert public.directory_entry == entry
    assert_receive {:mcp_probe_saved, @tenant, canonical, ^entry}
    assert canonical["endpoint"] == entry["endpoint"]
    assert canonical["auth_method"] == "bearer"
    assert canonical["credentials"] == %{"token" => "replacement"}
    refute_received {:mcp_probe, _, _}

    assert {:ok, _} =
             MCPConnections.update(data.principal, @tenant, "connection-id", 3, %{}, options)

    assert_receive {:mcp_resolve, @tenant, "connection-id"}

    assert_receive {:mcp_probe_saved, @tenant, %{"credentials" => %{"token" => "saved-secret"}},
                    ^entry}
  end

  test "a listed probe cannot persist a different entry or revision than the proposal", data do
    {entry, checked, options} = listed(data)

    input = %{
      "listing" => %{
        "directory_id" => entry["directory_id"],
        "integration_id" => entry["integration_id"],
        "entry_revision" => entry["revision"],
        "page" => %{}
      },
      "credentials" => %{"token" => "synthetic"}
    }

    for changed <- [
          Map.put(entry, "directory_id", "another-directory"),
          Map.put(entry, "integration_id", "another-entry"),
          Map.put(entry, "revision", 2),
          Map.put(entry, "authentication", %{"type" => "none"})
        ] do
      changed_check = %{
        checked
        | connection:
            Map.merge(checked.connection, %{
              directory_entry: changed,
              directory_id: changed["directory_id"] <> "/" <> changed["integration_id"]
            })
      }

      changed_options =
        Keyword.put(
          options,
          :mcp_connection_probe,
          {MCPProbeFixture, {self(), {:ok, changed_check}, entry}}
        )

      assert {:error, :mcp_connection_failed} =
               MCPConnections.connect(data.principal, @tenant, input, changed_options)

      refute_received {:mcp_create, _, _, _}
    end
  end

  test "listed reconnect requires fresh credentials and the retained generation", data do
    {entry, checked, options} = listed(data)
    saved = Map.merge(checked.connection, %{generation: 4, status: "revoked"})

    options =
      Keyword.put(options, :mcp_connection_repository, {MCPRepositoryFixture, {self(), saved}})

    input = %{"credentials" => %{"token" => "fresh"}}

    assert {:error, :invalid_mcp_configuration} =
             MCPConnections.reconnect(data.principal, @tenant, "connection-id", 4, %{}, options)

    assert {:error, :stale_mcp_connection} =
             MCPConnections.reconnect(data.principal, @tenant, "connection-id", 3, input, options)

    refute_received {:mcp_probe_saved, _, _, _}
    refute_received {:mcp_resolve, _, _}

    assert {:ok, public} =
             MCPConnections.reconnect(data.principal, @tenant, "connection-id", 4, input, options)

    assert public.directory_entry == entry
    assert_receive {:mcp_probe_saved, @tenant, %{"credentials" => %{"token" => "fresh"}}, ^entry}
    assert_receive {:mcp_replace, @tenant, "connection-id", 4, _}
    refute_received {:mcp_probe, _, _}
    refute_received {:mcp_resolve, _, _}
  end

  test "updates and disconnects preserve exact identity and observed generation", data do
    assert {:ok, updated} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "connection-id",
               3,
               data.input,
               data.options
             )

    assert updated.generation == 4
    assert_receive {:mcp_replace, @tenant, "connection-id", 3, _}

    assert {:ok, _} =
             MCPConnections.disconnect(data.principal, @tenant, "connection-id", 4, data.options)

    assert_receive {:mcp_revoke, @tenant, "connection-id", 4}

    assert {:error, :invalid_mcp_connection} =
             MCPConnections.disconnect(data.principal, @tenant, "connection-id", 0, data.options)
  end

  test "a deleted tenant cannot trigger a network probe", data do
    options =
      Keyword.put(
        data.options,
        :credential_repository,
        {MCPRepositoryFixture, {self(), :missing}}
      )

    assert {:error, :not_found} =
             MCPConnections.connect(data.principal, @tenant, data.input, options)

    refute_received {:mcp_probe, _, _}
    refute_received {:mcp_create, _, _, _}
  end

  test "omitted credentials reuse the saved secret only for the same endpoint and method", data do
    input = Map.delete(data.input, "credentials")

    assert {:ok, _} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "connection-id",
               3,
               input,
               data.options
             )

    assert_receive {:mcp_probe, @tenant, %{"credentials" => %{"token" => "saved-secret"}}}

    for changed <- [
          Map.put(input, "endpoint", "https://different.test/mcp"),
          Map.put(input, "auth_method", "basic")
        ] do
      assert {:error, :invalid_mcp_configuration} =
               MCPConnections.update(
                 data.principal,
                 @tenant,
                 "connection-id",
                 3,
                 changed,
                 data.options
               )
    end

    refute_received {:mcp_probe, _, _}

    assert {:error, :invalid_mcp_configuration} =
             MCPConnections.connect(data.principal, @tenant, input, data.options)
  end

  test "stale edits fail before probing even with replacement credentials", data do
    assert {:error, :stale_mcp_connection} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "connection-id",
               2,
               data.input,
               data.options
             )

    refute_received {:mcp_probe, _, _}
    refute_received {:mcp_replace, _, _, _, _}
  end

  test "fresh replacement repairs an unreadable old secret without resolving it", data do
    options =
      Keyword.put(
        data.options,
        :mcp_connection_repository,
        {MCPRepositoryFixture, {self(), :unreadable}}
      )

    assert {:ok, %{generation: 4}} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "connection-id",
               3,
               data.input,
               options
             )

    refute_received {:mcp_resolve, _, _}
    assert_receive {:mcp_replace, @tenant, "connection-id", 3, %{"token" => "synthetic"}}

    assert {:error, :mcp_credentials_unavailable} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "connection-id",
               3,
               Map.delete(data.input, "credentials"),
               options
             )

    assert_receive {:mcp_resolve, @tenant, "connection-id"}
    refute_received {:mcp_replace, _, _, _, _}
  end

  test "explicit reconnect restores a revoked identity with fresh credentials and its observed generation",
       data do
    assert {:ok, record} =
             MCPConnections.reconnect(
               data.principal,
               @tenant,
               "revoked-connection",
               4,
               data.input,
               data.options
             )

    assert record.id == "revoked-connection"
    assert record.namespace == "stable"
    assert record.generation == 5
    assert_receive {:mcp_replace, @tenant, "revoked-connection", 4, %{"token" => "synthetic"}}
    refute_received {:mcp_resolve, _, _}
  end

  test "a duplicate appearing after lookup supplies a reconnect proposal without restoring it",
       data do
    options =
      Keyword.put(
        data.options,
        :mcp_connection_repository,
        {MCPRepositoryFixture, {self(), :duplicate_revoked}}
      )

    assert {:error, {:mcp_reconnect_required, %{id: "revoked-connection", generation: 4}}} =
             MCPConnections.connect(data.principal, @tenant, data.input, options)

    assert_receive {:mcp_probe, @tenant, _}
    refute_received {:mcp_resolve, _, _}
    refute_received {:mcp_replace, _, _, _, _}
  end

  test "reconnect cannot substitute the retained endpoint or directory identity", data do
    for changed <- [
          %{data.checked.connection | endpoint: "https://other.example.test/mcp"},
          %{data.checked.connection | directory_id: "other-directory-entry"}
        ] do
      checked = %{data.checked | connection: changed}

      options =
        Keyword.put(
          data.options,
          :mcp_connection_probe,
          {MCPProbeFixture, {self(), {:ok, checked}}}
        )

      assert {:error, :invalid_mcp_configuration} =
               MCPConnections.reconnect(
                 data.principal,
                 @tenant,
                 "revoked-connection",
                 4,
                 data.input,
                 options
               )

      refute_received {:mcp_replace, _, _, _, _}
    end
  end

  test "reconnect requires a revoked current identity, fresh fields and current write authority",
       data do
    assert {:error, :stale_mcp_connection} =
             MCPConnections.reconnect(
               data.principal,
               @tenant,
               "revoked-connection",
               3,
               data.input,
               data.options
             )

    assert {:error, :mcp_reconnect_not_required} =
             MCPConnections.reconnect(
               data.principal,
               @tenant,
               "connection-id",
               3,
               data.input,
               data.options
             )

    assert {:error, :invalid_mcp_configuration} =
             MCPConnections.reconnect(
               data.principal,
               @tenant,
               "revoked-connection",
               4,
               Map.delete(data.input, "credentials"),
               data.options
             )

    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}

    assert {:error, :forbidden} =
             MCPConnections.reconnect(
               reader,
               @tenant,
               "revoked-connection",
               4,
               data.input,
               data.options
             )

    assert {:error, :mcp_connection_revoked} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "revoked-connection",
               4,
               data.input,
               data.options
             )

    refute_received {:mcp_probe, _, _}
    refute_received {:mcp_resolve, _, _}
    refute_received {:mcp_replace, _, _, _, _}

    options = Keyword.put(data.options, :refresh_authority, fn -> {:ok, reader} end)

    assert {:error, :forbidden} =
             MCPConnections.reconnect(
               data.principal,
               @tenant,
               "revoked-connection",
               4,
               data.input,
               options
             )

    refute_received {:mcp_replace, _, _, _, _}
  end

  test "preflight requires current tenant write authority and accepts no credentials", data do
    input = %{"endpoint" => data.input["endpoint"], "revision" => "draft-7"}
    result = %{endpoint: input["endpoint"], revision: "draft-7", outcome: :unknown}

    options =
      Keyword.put(data.options, :mcp_preflight, {MCPProbeFixture, {self(), {:ok, result}}})

    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}
    assert {:error, :forbidden} = MCPConnections.preflight(reader, @tenant, input, options)

    assert {:error, :invalid_mcp_preflight} =
             MCPConnections.preflight(
               data.principal,
               @tenant,
               Map.put(input, "credentials", %{}),
               options
             )

    refute_received {:mcp_preflight, _, _}
    assert {:ok, ^result} = MCPConnections.preflight(data.principal, @tenant, input, options)
    assert_receive {:mcp_preflight, @tenant, ^input}
    revoked = %{data.principal | grants: MapSet.new()}
    options = Keyword.put(options, :refresh_authority, fn -> {:ok, revoked} end)

    assert {:error, :forbidden} =
             MCPConnections.preflight(data.principal, @tenant, input, options)

    refute_received {:mcp_create, _, _, _}
  end

  test "static tool refresh uses saved credentials and writes only catalog metadata", data do
    checked = %{
      data.checked
      | connection: Map.put(data.checked.connection, :catalog, [%{"name" => "lookup"}])
    }

    options =
      Keyword.put(
        data.options,
        :mcp_connection_probe,
        {MCPProbeFixture, {self(), {:ok, checked}}}
      )

    assert {:ok, public} =
             MCPConnections.refresh_tools(data.principal, @tenant, "connection-id", 3, options)

    assert public.generation == 3
    assert public.auth_method == "bearer"
    assert public.tool_count == 1
    assert_receive {:mcp_probe, @tenant, %{"credentials" => %{"token" => "saved-secret"}}}

    assert_receive {:mcp_catalog, @tenant, "connection-id", 3,
                    %{server_name: "Calendar", catalog: [%{"name" => "lookup"}]}}

    refute_received {:mcp_replace, _, _, _, _}
    refute_received {:mcp_create, _, _, _}
    refute inspect(public) =~ "saved-secret"

    assert {:error, :stale_mcp_connection} =
             MCPConnections.refresh_tools(data.principal, @tenant, "connection-id", 2, options)

    refute_received {:mcp_probe, _, _}

    options =
      Keyword.put(options, :refresh_authority, fn ->
        {:ok, %{data.principal | grants: MapSet.new()}}
      end)

    assert {:error, :forbidden} =
             MCPConnections.refresh_tools(data.principal, @tenant, "connection-id", 3, options)

    refute_received {:mcp_catalog, _, _, _, _}
  end

  test "listed preflight remains authorized, credentialless and bound to the returned entry",
       data do
    reference = %{
      "directory_id" => "public",
      "integration_id" => "calendar",
      "entry_revision" => 1,
      "page" => %{}
    }

    input = %{"listing" => reference, "revision" => "draft-9"}
    snapshot = Map.merge(reference, %{"revision" => 1, "endpoint" => data.input["endpoint"]})
    result = %{endpoint: data.input["endpoint"], revision: "draft-9", listing: snapshot}

    options =
      Keyword.put(data.options, :mcp_preflight, {MCPProbeFixture, {self(), {:ok, result}}})

    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}

    assert {:error, :forbidden} = MCPConnections.preflight(reader, @tenant, input, options)

    for invalid <- [
          Map.put(input, "credentials", %{}),
          Map.put(input, "endpoint", "https://other.example.test/mcp"),
          Map.put(input, "auth_method", "none"),
          Map.put(input, "revision", ""),
          Map.put(input, "listing", nil),
          put_in(input, ["listing", "page", "q"], String.duplicate("a", 8193))
        ] do
      assert {:error, :invalid_mcp_preflight} =
               MCPConnections.preflight(data.principal, @tenant, invalid, options)
    end

    refute_received {:mcp_preflight, _, _}
    assert {:ok, ^result} = MCPConnections.preflight(data.principal, @tenant, input, options)
    assert_receive {:mcp_preflight, @tenant, ^input}

    for mismatched <- [
          Map.put(result, :revision, "old-draft"),
          Map.put(result, :endpoint, "https://other.example.test/mcp"),
          Map.delete(result, :listing),
          put_in(result, [:listing, "directory_id"], "other"),
          put_in(result, [:listing, "integration_id"], "other"),
          put_in(result, [:listing, "revision"], 2)
        ] do
      mismatch_options =
        Keyword.put(options, :mcp_preflight, {MCPProbeFixture, {self(), {:ok, mismatched}}})

      assert {:error, :mcp_discovery_unavailable} =
               MCPConnections.preflight(data.principal, @tenant, input, mismatch_options)
    end

    revoked = Keyword.put(options, :refresh_authority, fn -> {:error, :expired_session} end)

    assert {:error, :mcp_authority_unavailable} =
             MCPConnections.preflight(data.principal, @tenant, input, revoked)

    refute_received {:mcp_create, _, _, _}
  end

  test "details authorize reads and return tools without credentials", data do
    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}
    assert {:ok, result} = MCPConnections.get(reader, @tenant, "connection-id", data.options)
    assert result.tools == [%{"name" => "list_events"}]
    refute Map.has_key?(result, :secrets)

    assert {:error, :forbidden} =
             MCPConnections.get(reader, "BBBBBBBBBBBBBBBB", "connection-id", data.options)

    refute_received {:mcp_probe, _, _}
  end

  defp listed(data) do
    entry = %{
      "directory_id" => "public-directory",
      "integration_id" => "calendar",
      "revision" => 1,
      "name" => "Directory Calendar",
      "endpoint" => data.input["endpoint"],
      "authentication" => %{"type" => "bearer"}
    }

    checked = %{
      data.checked
      | connection:
          Map.merge(data.checked.connection, %{
            directory_id: "public-directory/calendar",
            directory_entry: entry,
            server_name: entry["name"]
          })
    }

    options =
      Keyword.put(
        data.options,
        :mcp_connection_probe,
        {MCPProbeFixture, {self(), {:ok, checked}}}
      )

    {entry, checked, options}
  end
end
