defmodule Vxpipe.Persistence.DemoSamplesTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{DemoSamples, DemoSetup, InstallationOperator, ProviderCredentials}
  alias Vxpipe.Identity.Principal

  alias Vxpipe.Persistence.{
    Repo,
    CredentialKeyring,
    CredentialStore,
    CallSpecStore,
    DemoTenantStore,
    ProviderCredentialStore
  }

  setup do
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      demo_tenant_repository: {DemoTenantStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]}
    ]

    {:ok, tenant} = DemoSetup.ensure_tenant(InstallationOperator.authority(), options)

    actor = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["tenants.write", "call_specs.write"]),
      assigned_tenants: %{tenant.key => :read_write},
      all_tenant_actions: MapSet.new()
    }

    [options: options, tenant: tenant, actor: actor]
  end

  test "uses existing demo binding and never creates a different tenant", context do
    assert {:ok, stored} = DemoTenantStore.fetch(Repo)
    assert stored.key == context.tenant.key
    other = "OTHERabcdefgh123"
    actor = %{context.actor | assigned_tenants: %{other => :read_write}}
    assert {:error, :not_found} = DemoSamples.install(actor, other, context.options)
    assert {:ok, ^stored} = DemoTenantStore.fetch(Repo)
  end

  test "first revision lookup is tenant-scoped, immutable and bounded", context do
    [entry | _] = DemoSamples.catalog("google")
    provision(context.tenant.key, ["deepgram", "google"], context.options)

    {:ok, first} =
      Vxpipe.Calls.save_authorized_call_spec(
        context.actor,
        context.tenant.key,
        entry.source,
        context.options
      )

    {:ok, _} =
      Vxpipe.Calls.save_authorized_call_spec(
        context.actor,
        context.tenant.key,
        Map.put(entry.source, :name, "Renamed"),
        Keyword.put(context.options, :call_spec_id, first.call_spec_id)
      )

    {:ok, second} =
      Vxpipe.Calls.save_authorized_call_spec(
        context.actor,
        context.tenant.key,
        entry.source,
        context.options
      )

    {:ok, _third} =
      Vxpipe.Calls.save_authorized_call_spec(
        context.actor,
        context.tenant.key,
        entry.source,
        context.options
      )

    assert {:ok, ids} = CallSpecStore.find_by_original_name(Repo, context.tenant.key, entry.name)
    assert ids == [first.call_spec_id, second.call_spec_id]
    assert {:ok, []} = CallSpecStore.find_by_original_name(Repo, "OTHERabcdefgh123", entry.name)
    assert {:ok, []} = CallSpecStore.find_by_original_name(Repo, context.tenant.key, "Renamed")

    assert {:ok, [conflict | _]} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    assert conflict.status == :conflict
  end

  test "inherited platform services require authoring permission before writes", context do
    provision(:platform, ["deepgram", "google"], context.options)

    assert {:error, :forbidden} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 0
    actor = %{context.actor | grants: MapSet.put(context.actor.grants, "platform_services.read")}
    assert {:ok, installed} = DemoSamples.install(actor, context.tenant.key, context.options)
    assert Enum.all?(installed, &(&1.status == :installed and &1.revision == 1))
  end

  test "installs and resumes under actual write-only actor beyond the directory page", context do
    provision(context.tenant.key, ["deepgram", "openai"], context.options)
    assert {:ok, first} = DemoSamples.install(context.actor, context.tenant.key, context.options)
    assert length(first) == 3
    assert Enum.all?(first, &(&1.status == :installed and &1.revision == 1))
    # Later unrelated specs would push the samples off the former first-100 directory.
    [entry | _] = DemoSamples.catalog("openai")

    for n <- 1..101 do
      {:ok, _} =
        Vxpipe.Calls.save_authorized_call_spec(
          context.actor,
          context.tenant.key,
          Map.put(entry.source, :name, "Unrelated #{n}"),
          context.options
        )
    end

    assert {:ok, ^first} = DemoSamples.install(context.actor, context.tenant.key, context.options)
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 104
    [sample | _] = first

    {:ok, _} =
      Vxpipe.Calls.save_authorized_call_spec(
        context.actor,
        context.tenant.key,
        Map.put(entry.source, :name, "Customized"),
        Keyword.put(context.options, :call_spec_id, sample.call_spec_id)
      )

    assert {:ok, [conflict | _]} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    assert conflict.status == :conflict

    assert {:ok, published} =
             CallSpecStore.fetch_published_revision(Repo, context.tenant.key, sample.call_spec_id)

    assert published.revision == 1
  end

  test "a missing demo binding is not created by installation", context do
    Repo.delete_all(Vxpipe.Persistence.Schema.InstallationSetup)

    assert {:error, :not_found} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    assert {:error, :not_found} = DemoTenantStore.fetch(Repo)
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 0
  end

  for provider <- ["zenmux", "deepseek", "openrouter", "fireworks"] do
    @provider provider
    test "installs #{@provider} samples with tenant-owned bindings", context do
      provision(context.tenant.key, ["deepgram", @provider], context.options)

      assert {:ok, installed} =
               DemoSamples.install(context.actor, context.tenant.key, context.options)

      assert Enum.all?(installed, &(&1.status == :installed and &1.revision == 1))

      assert {:ok, source} =
               CallSpecStore.fetch_revision(
                 Repo,
                 context.tenant.key,
                 hd(installed).call_spec_id,
                 1
               )

      assert source.source["defaults"]["capabilities"]["model_inference"]["provider"] == @provider
    end
  end

  test "concurrent installers reuse IDs and resume an unpublished matching revision", context do
    provision(context.tenant.key, ["deepgram", "google"], context.options)

    results =
      1..2
      |> Task.async_stream(
        fn _ ->
          DemoSamples.install(context.actor, context.tenant.key, context.options)
        end, max_concurrency: 2, timeout: :infinity)
      |> Enum.map(fn {:ok, {:ok, result}} -> result end)

    [first, second] = results
    assert first == second
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 3
    [entry | _] = DemoSamples.catalog("google")
    id = hd(first).call_spec_id

    assert {:ok, %{revision: 2}} =
             Vxpipe.Calls.save_authorized_call_spec(
               context.actor,
               context.tenant.key,
               entry.source,
               Keyword.put(context.options, :call_spec_id, id)
             )

    assert {:ok, [resumed | _]} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    assert resumed.call_spec_id == id
    assert resumed.revision == 2

    assert {:ok, %{revision: 2}} =
             CallSpecStore.fetch_published_revision(Repo, context.tenant.key, id)
  end

  test "missing, alternate-named and unreadable shadow credentials cannot satisfy prerequisites",
       context do
    assert {:error, :sample_prerequisites_missing} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    for provider <- ["deepgram", "google"] do
      {:ok, _} =
        ProviderCredentials.provision(
          context.tenant.key,
          provider,
          "alternate",
          "api_key",
          %{"api_key" => "synthetic-alternate"},
          context.options
        )
    end

    assert {:error, :sample_prerequisites_missing} =
             DemoSamples.install(context.actor, context.tenant.key, context.options)

    provision(:platform, ["deepgram", "google"], context.options)
    actor = %{context.actor | grants: MapSet.put(context.actor.grants, "platform_services.read")}

    {:ok, own} =
      ProviderCredentials.provision(
        context.tenant.key,
        "deepgram",
        "deepgram",
        "api_key",
        %{"api_key" => "synthetic-own"},
        context.options
      )

    stored = Repo.get_by!(Vxpipe.Persistence.Schema.ProviderCredential, public_id: own.id)

    Repo.update!(
      Ecto.Changeset.change(stored,
        encrypted_payload: :crypto.strong_rand_bytes(byte_size(stored.encrypted_payload))
      )
    )

    assert {:error, :sample_prerequisites_missing} =
             DemoSamples.install(actor, context.tenant.key, context.options)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 0
    assert :ok = ProviderCredentials.delete(context.tenant.key, own.id, context.options)
    assert {:ok, installed} = DemoSamples.install(actor, context.tenant.key, context.options)
    assert Enum.all?(installed, &(&1.status == :installed))
  end

  defp provision(scope, providers, options) do
    for provider <- providers do
      {:ok, _} =
        ProviderCredentials.provision(
          scope,
          provider,
          provider,
          "api_key",
          %{"api_key" => "synthetic-test-key"},
          options
        )
    end
  end
end
