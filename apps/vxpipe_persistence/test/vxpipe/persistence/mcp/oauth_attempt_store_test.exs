defmodule Vxpipe.Persistence.MCP.OAuthAttemptStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.OAuthAttemptStore
  @now ~U[2026-11-06 12:00:00.000000Z]

  setup do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("OAuth tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("key", %{"key" => :crypto.strong_rand_bytes(32)})

    attributes = %{
      connection_id: Ecto.UUID.generate(),
      generation: 1,
      user_id: "user",
      session_id: "session",
      issuer: "https://auth.example.test",
      redirect_uri: "https://console.example.test/oauth/mcp/callback",
      resource: "https://mcp.example.test/mcp",
      draft_revision: "draft-1",
      installation_revision: 2,
      expires_at: DateTime.add(@now, 300),
      state: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    }

    authority =
      Map.take(attributes, [:user_id, :session_id, :installation_revision, :redirect_uri])

    %{
      tenant: tenant.key,
      attributes: attributes,
      authority: authority,
      context: [repo: Repo, keyring: keyring, now: fn -> @now end]
    }
  end

  test "repository outages return a fixed error and recovery leaves the attempt claimable",
       data do
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})
    previous = Repo.get_dynamic_repo()
    name = Vxpipe.Persistence.MCPAttemptRestartRepo
    repository = start_supervised!({Repo, name: name, pool_size: 1})
    monitor = Process.monitor(repository)
    stop_supervised!(Repo)
    assert_receive {:DOWN, ^monitor, :process, ^repository, :shutdown}

    try do
      for unavailable <- [name, repository] do
        Repo.put_dynamic_repo(unavailable)

        for operation <- attempt_operations(data, data.context) do
          assert {:error, :mcp_oauth_storage_unavailable} = operation.()
        end
      end
    after
      Repo.put_dynamic_repo(previous)
    end

    assert {:ok, tenant} =
             OAuthAttemptStore.locate(data.context, data.attributes.state, data.authority)

    assert tenant == data.tenant

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )
  end

  test "programmer errors are not classified as invalid attempts or storage outages", data do
    for operation <- attempt_operations(data, Keyword.delete(data.context, :repo)) do
      assert_raise KeyError, operation
    end
  end

  defp attempt_operations(data, context) do
    [
      fn -> OAuthAttemptStore.issue(context, data.tenant, data.attributes, %{}) end,
      fn -> OAuthAttemptStore.locate(context, data.attributes.state, data.authority) end,
      fn ->
        OAuthAttemptStore.claim(context, data.tenant, data.attributes.state, data.authority)
      end,
      fn -> OAuthAttemptStore.prune(context, 100) end
    ]
  end

  test "replacement intent and generation survive claim and cannot be changed outside ciphertext",
       data do
    attributes = Map.merge(data.attributes, %{operation: "replace", generation: 7})
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, attributes, %{})

    assert {:ok, claimed} =
             OAuthAttemptStore.claim(data.context, data.tenant, attributes.state, data.authority)

    assert claimed.attempt.operation == "replace"
    assert claimed.attempt.generation == 7

    attributes = %{attributes | state: attributes.state <> "tamper"}
    assert {:ok, issued} = OAuthAttemptStore.issue(data.context, data.tenant, attributes, %{})
    record = Repo.get_by!(Vxpipe.Persistence.Schema.MCPOAuthAttempt, public_id: issued.id)

    record
    |> Ecto.Changeset.change(binding: Map.put(record.binding, "operation", "create"))
    |> Repo.update!()

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(data.context, data.tenant, attributes.state, data.authority)
  end

  test "return location is restored from the authenticated attempt binding", data do
    path = "/t/" <> data.tenant <> "/services/search?q=calendar"
    attributes = Map.put(data.attributes, :return_to, path)
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, attributes, %{})

    assert {:ok, claimed} =
             OAuthAttemptStore.claim(data.context, data.tenant, attributes.state, data.authority)

    assert claimed.attempt.return_to == path

    attributes = %{attributes | state: attributes.state <> "tamper"}
    assert {:ok, issued} = OAuthAttemptStore.issue(data.context, data.tenant, attributes, %{})
    record = Repo.get_by!(Vxpipe.Persistence.Schema.MCPOAuthAttempt, public_id: issued.id)

    record
    |> Ecto.Changeset.change(binding: Map.put(record.binding, "return_to", "https://other.test"))
    |> Repo.update!()

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(data.context, data.tenant, attributes.state, data.authority)
  end

  test "unknown operation cannot enter durable attempt storage", data do
    assert {:error, :invalid_oauth_attempt} =
             OAuthAttemptStore.issue(
               data.context,
               data.tenant,
               Map.put(data.attributes, :operation, "upsert"),
               %{}
             )
  end

  test "state digest column cannot replace authenticated lookup state", data do
    assert {:ok, attempt} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})

    query =
      from(a in Vxpipe.Persistence.Schema.MCPOAuthAttempt, where: a.public_id == ^attempt.id)

    other_state = String.duplicate("other", 10)
    original_digest = :crypto.hash(:sha256, data.attributes.state)
    Repo.update_all(query, set: [state_digest: :crypto.hash(:sha256, other_state)])

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(data.context, data.tenant, other_state, data.authority)

    Repo.update_all(query, set: [state_digest: original_digest])

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )
  end

  test "expiry column cannot extend authenticated attempt lifetime", data do
    assert {:ok, attempt} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})

    query =
      from(a in Vxpipe.Persistence.Schema.MCPOAuthAttempt, where: a.public_id == ^attempt.id)

    Repo.update_all(query, set: [expires_at: DateTime.add(@now, 900)])
    later = Keyword.put(data.context, :now, fn -> DateTime.add(@now, 600) end)

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(later, data.tenant, data.attributes.state, data.authority)

    Repo.update_all(query, set: [expires_at: data.attributes.expires_at])

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )
  end

  test "bounded pruning erases expired and claimed attempts while retaining live pending keys",
       data do
    for {suffix, expires, claim?} <- [
          {"expired", 30, false},
          {"claimed", 300, true},
          {"pending", 300, false}
        ] do
      attributes = %{
        data.attributes
        | state: data.attributes.state <> suffix,
          expires_at: DateTime.add(@now, expires)
      }

      assert {:ok, _} =
               OAuthAttemptStore.issue(data.context, data.tenant, attributes, %{
                 "verifier" => "private-prune-marker"
               })

      if claim?,
        do:
          assert(
            {:ok, _} =
              OAuthAttemptStore.claim(data.context, data.tenant, attributes.state, data.authority)
          )
    end

    context =
      data.context
      |> Keyword.delete(:keyring)
      |> Keyword.put(:now, fn -> DateTime.add(@now, 30) end)

    assert {:ok, %{processed: 1, remaining: 1, pending_by_key: %{"key" => 1}}} =
             OAuthAttemptStore.prune(context, 1)

    assert {:ok, %{processed: 1, remaining: 0, pending_by_key: %{"key" => 1}}} =
             OAuthAttemptStore.prune(context, 1)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.MCPOAuthAttempt, :count) == 1

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state <> "pending",
               data.authority
             )

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state <> "expired",
               data.authority
             )
  end

  test "pruning rejects invalid batch bounds", data do
    for size <- [0, 501, -1, "10"],
        do:
          assert(
            {:error, :invalid_oauth_prune_batch_size} =
              OAuthAttemptStore.prune(data.context, size)
          )
  end

  test "operator prune command uses configured storage and prints only counts", data do
    previous = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)

    on_exit(fn ->
      Mix.shell(shell)

      if previous,
        do: Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous),
        else: Application.delete_env(:vxpipe_calls, Vxpipe.Calls)
    end)

    assert {:ok, _} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{
               "verifier" => "private-cli-marker"
             })

    context = Keyword.put(data.context, :now, fn -> DateTime.add(@now, 300) end)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      mcp_oauth_attempt_repository: {OAuthAttemptStore, context}
    )

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Vxpipe.McpOauth.Prune.run(["--batch-size", "1"])
      end)

    assert JSON.decode!(output) == %{"processed" => 1, "remaining" => 0, "pending_by_key" => %{}}
    refute output =~ data.tenant
    refute output =~ "private-cli-marker"

    error =
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Vxpipe.McpOauth.Prune.run(["--state", "private-cli-marker"])
      end

    refute Exception.message(error) =~ "private-cli-marker"
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, [])

    assert_raise Mix.Error, ~r/OAuth attempt storage is not configured/, fn ->
      Mix.Tasks.Vxpipe.McpOauth.Prune.run([])
    end
  end

  test "encrypted attempt is claimed once and consumed ciphertext is erased", data do
    assert {:ok, issued} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{
               "verifier" => "private-verifier"
             })

    stored =
      Repo.one!(
        from(a in "tenant_mcp_oauth_attempts",
          select: %{encrypted_payload: a.encrypted_payload, state_digest: a.state_digest}
        )
      )

    refute stored.encrypted_payload =~ "private-verifier"
    refute stored.state_digest == data.attributes.state

    assert {:ok, attempt} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )

    assert attempt.attempt.id == issued.id
    assert attempt.attempt.connection_id == data.attributes.connection_id
    assert attempt.secrets == %{"verifier" => "private-verifier"}
    refute inspect(attempt) =~ "private-verifier"

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )

    assert Repo.one!(from(a in "tenant_mcp_oauth_attempts", select: is_nil(a.encrypted_payload)))
  end

  test "callback scope lookup requires the bound browser identity without consuming state",
       data do
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})

    assert {:ok, tenant} =
             OAuthAttemptStore.locate(data.context, data.attributes.state, data.authority)

    assert tenant == data.tenant

    for authority <- [
          %{data.authority | user_id: "other"},
          %{data.authority | session_id: "other"},
          %{}
        ] do
      assert {:error, :oauth_attempt_unavailable} =
               OAuthAttemptStore.locate(data.context, data.attributes.state, authority)
    end

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.locate(data.context, data.attributes.state, data.authority)
  end

  test "expired and unknown state cannot reveal callback scope", data do
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})
    expired = Keyword.put(data.context, :now, fn -> data.attributes.expires_at end)

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.locate(expired, data.attributes.state, data.authority)

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.locate(data.context, String.duplicate("x", 43), data.authority)
  end

  test "session, installation revision and callback bind the claim", data do
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})

    for authority <- [
          %{data.authority | session_id: "other"},
          %{data.authority | installation_revision: 3},
          %{data.authority | redirect_uri: "https://other.test/callback"}
        ] do
      assert {:error, :oauth_attempt_unavailable} =
               OAuthAttemptStore.claim(
                 data.context,
                 data.tenant,
                 data.attributes.state,
                 authority
               )
    end

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )
  end

  test "old and new key attempts survive missing-key claims without consumption", data do
    {:ok, old_key} = CredentialKeyring.fetch(Keyword.fetch!(data.context, :keyring), "key")
    new_key = :crypto.strong_rand_bytes(32)
    {:ok, both} = CredentialKeyring.new("new", %{"key" => old_key, "new" => new_key})
    {:ok, only_new} = CredentialKeyring.new("new", %{"new" => new_key})
    current = Keyword.put(data.context, :keyring, both)
    retired = Keyword.put(data.context, :keyring, only_new)

    for {suffix, writer, missing, reader} <- [
          {"old", data.context, retired, current},
          {"new", current, data.context, retired}
        ] do
      attributes = %{data.attributes | state: data.attributes.state <> suffix}

      assert {:ok, issued} =
               OAuthAttemptStore.issue(writer, data.tenant, attributes, %{"proof" => suffix})

      assert {:error, :credential_key_unavailable} =
               OAuthAttemptStore.claim(missing, data.tenant, attributes.state, data.authority)

      record = Repo.get_by!(Vxpipe.Persistence.Schema.MCPOAuthAttempt, public_id: issued.id)
      assert record.claimed_at == nil
      assert is_binary(record.encrypted_payload)

      assert {:ok, claimed} =
               OAuthAttemptStore.claim(reader, data.tenant, attributes.state, data.authority)

      assert claimed.secrets == %{"proof" => suffix}
    end
  end

  test "missing encryption key is operational failure and inserts no attempt", data do
    context = Keyword.delete(data.context, :keyring)

    assert {:error, :credential_key_unavailable} =
             OAuthAttemptStore.issue(context, data.tenant, data.attributes, %{})

    assert Repo.aggregate("tenant_mcp_oauth_attempts", :count) == 0
  end

  test "expiry and tenant isolation reject claims without consuming a valid attempt", data do
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(
               data.context,
               "another-tenant",
               data.attributes.state,
               data.authority
             )

    expired_context = Keyword.put(data.context, :now, fn -> data.attributes.expires_at end)

    assert {:error, :oauth_attempt_unavailable} =
             OAuthAttemptStore.claim(
               expired_context,
               data.tenant,
               data.attributes.state,
               data.authority
             )

    assert {:ok, _} =
             OAuthAttemptStore.claim(
               data.context,
               data.tenant,
               data.attributes.state,
               data.authority
             )
  end

  test "expired and overlong attempts fail and a tenant has bounded pending attempts", data do
    assert {:error, :invalid_oauth_attempt} =
             OAuthAttemptStore.issue(
               data.context,
               data.tenant,
               %{data.attributes | expires_at: DateTime.add(@now, 601)},
               %{}
             )

    for _ <- 1..8 do
      attrs = %{
        data.attributes
        | state: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      }

      assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, attrs, %{})
    end

    assert {:error, :oauth_attempt_busy} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})
  end
end
