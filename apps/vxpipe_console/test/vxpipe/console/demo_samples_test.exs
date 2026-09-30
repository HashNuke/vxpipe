defmodule Vxpipe.Console.DemoSamplesTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.Calls.{Administration, InstallationOperator, ProviderCredentials, Tenant}
  alias Vxpipe.Console.DemoSamples

  alias Vxpipe.Persistence.{
    AdminStore,
    CredentialKeyring,
    CredentialStore,
    CallSpecStore,
    ProviderCredentialStore,
    Repo
  }

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "ships three parseable, versioned sample call specs" do
    entries = DemoSamples.catalog("google")

    assert Enum.map(entries, & &1.id) == [
             "sample-voice-conversation",
             "sample-agent-handoff",
             "sample-human-handoff"
           ]

    for entry <- entries do
      assert entry.version == 1

      assert {:ok, call_spec} =
               CallSpec.new(entry.source, resource_id: entry.id, revision: 1)

      assert call_spec.default_capabilities.model_inference.provider == "google"
      assert call_spec.default_capabilities.text_to_speech.model == "flux"
      assert call_spec.default_capabilities.text_to_speech.options == %{"voice" => "haley"}
    end

    assert Enum.all?(DemoSamples.catalog("zenmux"), fn entry ->
             {:ok, call_spec} =
               CallSpec.new(entry.source, resource_id: entry.id, revision: 1)

             call_spec.default_capabilities.model_inference.provider == "zenmux"
           end)
  end

  test "does not install samples without both speech and model credentials" do
    tenant = %Tenant{
      key: "DEMOabcdefgh1234",
      name: "DemoTenant",
      inserted_at: ~U[2026-09-18 05:00:00Z]
    }

    assert {:error, :sample_prerequisites_missing} =
             DemoSamples.install(
               InstallationOperator.authority(),
               tenant.key,
               provider_credential_repository: {
                 Vxpipe.Console.Test.OperatorCredentialRepository,
                 {self(), {:ok, %{tenant: %{key: tenant.key, name: tenant.name}, bindings: []}}}
               }
             )
  end

  test "new direct model services install publishable samples with scoped credentials" do
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo},
      admin_repository: {AdminStore, Repo}
    ]

    assert {:ok, _} =
             ProviderCredentials.provision(
               :platform,
               "deepgram",
               "deepgram",
               "api_key",
               %{"api_key" => "synthetic-speech"},
               options
             )

    for {provider, model} <- [
          {"openai", "gpt-5"},
          {"deepseek", "deepseek-flash"},
          {"openrouter", "google/gemini-3.5-flash-lite"},
          {"fireworks", "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"}
        ] do
      assert {:ok, tenant, _} = Administration.bootstrap_tenant(provider, [:admin], options)

      assert {:ok, platform} =
               ProviderCredentials.provision(
                 :platform,
                 provider,
                 provider,
                 "api_key",
                 %{"api_key" => "synthetic-platform"},
                 options
               )

      assert {:ok, inherited} =
               ProviderCredentials.resolve(tenant.key, provider, provider, options)

      assert inherited.credential.id == platform.id

      # Only this model service is active for this tenant; earlier loop providers
      # are removed from platform scope after their acceptance below.
      assert {:ok, installed} =
               DemoSamples.install(InstallationOperator.authority(), tenant.key, options)

      assert Enum.map(installed, &{&1.id, &1.status, &1.revision}) == expected_installations()

      assert {:ok, publication} =
               Vxpipe.Calls.fetch_call_spec(tenant.key, "sample-voice-conversation", 1, options)

      selection = publication.source["defaults"]["capabilities"]["model_inference"]
      assert selection["provider"] == provider
      assert selection["model"] == model
      assert selection["credential_name"] == provider

      assert {:ok, own} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 provider,
                 "api_key",
                 %{"api_key" => "synthetic-tenant"},
                 options
               )

      assert {:ok, overridden} =
               ProviderCredentials.resolve(tenant.key, provider, provider, options)

      assert overridden.credential.id == own.id
      assert overridden.payload == %{"api_key" => "synthetic-tenant"}
      refute inspect(overridden.credential) =~ "synthetic-tenant"
      assert :ok = ProviderCredentials.delete(:platform, platform.id, options)
    end
  end

  test "requires installation operator authority" do
    assert {:error, :installation_operator_required} =
             DemoSamples.install(:anonymous, "DEMOabcdefgh1234", [])
  end

  test "installs and republishes the three call specs idempotently" do
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    credential_context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, credential_context},
      call_spec_repository: {CallSpecStore, Repo},
      admin_repository: {AdminStore, Repo}
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("DemoTenant", [:admin], options)

    for {provider, secret} <- [{"deepgram", "deepgram-private"}, {"google", "google-private"}] do
      assert {:ok, _credential} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 provider,
                 "api_key",
                 %{"api_key" => secret},
                 options
               )
    end

    authority = InstallationOperator.authority()

    concurrent =
      1..2
      |> Task.async_stream(
        fn _request -> DemoSamples.install(authority, tenant.key, options) end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {:ok, result}} -> result end)

    assert length(concurrent) == 2

    for result <- concurrent do
      assert Enum.map(result, &{&1.id, &1.status, &1.revision}) == expected_installations()
    end

    assert {:ok, second} = DemoSamples.install(authority, tenant.key, options)
    assert Enum.map(second, &{&1.id, &1.status, &1.revision}) == expected_installations()

    assert {:ok, page} = Vxpipe.Calls.list_operator_call_specs(authority, tenant.key, options)
    assert page.total == 3
    assert Enum.all?(page.call_specs, &(&1.latest_revision == 1))
  end

  test "installs with inherited exact bindings and refuses an unreadable tenant credential" do
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo},
      admin_repository: {AdminStore, Repo}
    ]

    assert {:ok, tenant, _} = Administration.bootstrap_tenant("Inherited demo", [:admin], options)

    for provider <- ["google", "deepgram"] do
      assert {:ok, _} =
               ProviderCredentials.provision(
                 :platform,
                 provider,
                 provider,
                 "api_key",
                 %{"api_key" => "synthetic-platform"},
                 options
               )
    end

    authority = InstallationOperator.authority()
    assert {:ok, installed} = DemoSamples.install(authority, tenant.key, options)
    assert Enum.map(installed, &{&1.id, &1.status, &1.revision}) == expected_installations()

    assert {:ok, own} =
             ProviderCredentials.provision(
               tenant.key,
               "deepgram",
               "deepgram",
               "api_key",
               %{"api_key" => "synthetic-own"},
               options
             )

    stored = Repo.get_by!(Vxpipe.Persistence.Schema.ProviderCredential, public_id: own.id)

    Repo.update!(
      Ecto.Changeset.change(stored,
        encrypted_payload: :crypto.strong_rand_bytes(byte_size(stored.encrypted_payload))
      )
    )

    assert {:error, :sample_prerequisites_missing} =
             DemoSamples.install(authority, tenant.key, options)

    assert :ok = ProviderCredentials.delete(tenant.key, own.id, options)

    assert {:ok, resumed} = DemoSamples.install(authority, tenant.key, options)
    assert Enum.map(resumed, &{&1.id, &1.status, &1.revision}) == expected_installations()

    [entry | _] = DemoSamples.catalog("google")
    edited = Map.put(entry.source, :name, "Operator's customized sample")

    assert {:ok, %{revision: 2}} =
             Vxpipe.Calls.save_call_spec(
               tenant.key,
               edited,
               Keyword.put(options, :call_spec_id, entry.id)
             )

    assert {:ok, [conflict | _]} = DemoSamples.install(authority, tenant.key, options)
    assert conflict.status == :conflict
    assert {:ok, page} = Vxpipe.Calls.list_operator_call_specs(authority, tenant.key, options)
    customized = Enum.find(page.call_specs, &(&1.id == entry.id))
    assert customized.latest_revision == 2
    assert customized.published_revision == 1
  end

  test "alternate credential names do not satisfy the fixed sample bindings" do
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo},
      admin_repository: {AdminStore, Repo}
    ]

    assert {:ok, tenant, _} = Administration.bootstrap_tenant("Named demo", [:admin], options)

    for provider <- ["google", "deepgram"] do
      assert {:ok, _} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 "alternate",
                 "api_key",
                 %{"api_key" => "synthetic-named"},
                 options
               )
    end

    assert {:error, :sample_prerequisites_missing} =
             DemoSamples.install(InstallationOperator.authority(), tenant.key, options)

    assert {:ok, %{total: 0}} =
             Vxpipe.Calls.list_operator_call_specs(
               InstallationOperator.authority(),
               tenant.key,
               options
             )
  end

  defp expected_installations do
    [
      {"sample-voice-conversation", :installed, 1},
      {"sample-agent-handoff", :installed, 1},
      {"sample-human-handoff", :installed, 1}
    ]
  end
end
