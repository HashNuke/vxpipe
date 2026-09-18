defmodule Vxpipe.Console.DemoSamplesTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.Calls.{Administration, InstallationOperator, ProviderCredentials, Tenant}
  alias Vxpipe.Console.DemoSamples

  alias Vxpipe.Persistence.{
    AdminStore,
    CredentialKeyring,
    CredentialStore,
    DefinitionStore,
    ProviderCredentialStore,
    Repo
  }

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "ships three parseable, versioned sample call definitions" do
    entries = DemoSamples.catalog("google")

    assert Enum.map(entries, & &1.id) == [
             "sample-voice-conversation",
             "sample-agent-handoff",
             "sample-human-handoff"
           ]

    for entry <- entries do
      assert entry.version == 1

      assert {:ok, definition} =
               CallDefinition.new(entry.source, resource_id: entry.id, revision: 1)

      assert definition.default_capabilities.model_inference.provider == "google"
    end

    assert Enum.all?(DemoSamples.catalog("zenmux"), fn entry ->
             {:ok, definition} =
               CallDefinition.new(entry.source, resource_id: entry.id, revision: 1)

             definition.default_capabilities.model_inference.provider == "zenmux"
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
               admin_repository: {
                 Vxpipe.Console.Test.AdminRepository,
                 {self(), {:ok, {tenant, [], [], false}}}
               }
             )
  end

  test "requires installation operator authority" do
    assert {:error, :installation_operator_required} =
             DemoSamples.install(:anonymous, "DEMOabcdefgh1234", [])
  end

  test "installs and republishes the three definitions idempotently" do
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    credential_context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, credential_context},
      definition_repository: {DefinitionStore, Repo},
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

    assert {:ok, page} = Vxpipe.Calls.list_operator_definitions(authority, tenant.key, options)
    assert page.total == 3
    assert Enum.all?(page.definitions, &(&1.latest_revision == 1))
  end

  defp expected_installations do
    [
      {"sample-voice-conversation", :installed, 1},
      {"sample-agent-handoff", :installed, 1},
      {"sample-human-handoff", :installed, 1}
    ]
  end
end
