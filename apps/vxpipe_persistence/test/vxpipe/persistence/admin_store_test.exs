defmodule Vxpipe.Persistence.AdminStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{Administration, Definitions, InstallationOperator}
  alias Vxpipe.Persistence.{AdminStore, CredentialStore, DefinitionStore, Repo}
  alias Vxpipe.Persistence.Schema.{Call, CallDefinition, DefinitionRevision, Tenant}
  alias Vxpipe.Persistence.TestUnavailableAdminRepo

  test "lists tenants in a deterministic bounded page with a total" do
    existing_total = Repo.aggregate(Tenant, :count)

    for {name, key} <- [
          {"Oldest", "AAAAAAAAAAAAAAAA"},
          {"Middle", "BBBBBBBBBBBBBBBB"},
          {"Newest", "CCCCCCCCCCCCCCCC"}
        ] do
      assert {:ok, _tenant, _issued} =
               Administration.bootstrap_tenant(name, [:admin],
                 credential_repository: {CredentialStore, Repo},
                 tenant_key_generator: fn -> key end
               )
    end

    assert {:ok, {ordered, total}} = AdminStore.list_tenants(Repo, existing_total + 3, 0)

    assert total == existing_total + 3
    assert Enum.map(Enum.take(ordered, 3), & &1.name) == ["Newest", "Middle", "Oldest"]

    assert {:ok, page} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               page: 2,
               limit: 2,
               admin_repository: {AdminStore, Repo}
             )

    assert page.page == 2
    assert page.page_size == 2
    assert page.total == existing_total + 3
    assert page.total_pages == div(existing_total + 4, 2)
    assert page.tenants == Enum.slice(ordered, 2, 2)

    assert {:ok, {[], ^total}} = AdminStore.list_tenants(Repo, 2, total + 1)
  end

  test "translates an unavailable repository into the port error contract" do
    assert {:error, :repository_unavailable} =
             AdminStore.list_tenants(TestUnavailableAdminRepo, 25, 0)

    assert {:error, :repository_unavailable} =
             AdminStore.list_definitions(TestUnavailableAdminRepo, "AAAAAAAAAAAAAAAA", 25, 0)
  end

  test "lists one tenant's definitions with latest and published versions and call totals" do
    options = [
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      tenant_key_generator: fn -> "AAAAAAAAAAAAAAAA" end,
      api_key_generator: fn -> "vxp_test-secret-value" end,
      uuid_generator:
        sequence([
          "11111111-1111-4111-8111-111111111111",
          "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        ]),
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        Vxpipe.Calls.TestTelephonyServiceRepository.repository([tenant])
      )

    assert {:ok, first} = Definitions.save(tenant.key, definition_input("First name"), options)
    assert {:ok, _published} = Definitions.publish(tenant.key, first.definition_id, 1, options)

    assert {:ok, second} =
             Definitions.save(
               tenant.key,
               definition_input("Current name"),
               Keyword.put(options, :definition_id, first.definition_id)
             )

    definition = Repo.get_by!(CallDefinition, public_id: first.definition_id)
    revision = Repo.get_by!(DefinitionRevision, call_definition_id: definition.id, revision: 2)

    Repo.insert!(
      Call.changeset(%Call{}, %{
        public_id: "22222222-2222-4222-8222-222222222222",
        participant_routes: %{},
        entry_caller: "caller",
        entry_receiver: "assistant",
        initial_variables: %{},
        resolved_plan: :erlang.term_to_binary(%{}),
        plan_digest: :crypto.strong_rand_bytes(32),
        state: :prepared,
        room_id: "33333333-3333-4333-8333-333333333333",
        created_at: ~U[2026-09-17 04:00:00Z],
        tenant_id: definition.tenant_id,
        definition_revision_id: revision.id
      })
    )

    assert {:ok, {listed_tenant, [summary], 1}} =
             AdminStore.list_definitions(Repo, tenant.key, 25, 0)

    assert listed_tenant.key == tenant.key
    assert listed_tenant.name == "Example tenant"
    assert summary.id == first.definition_id
    assert summary.name == "Current name"
    assert summary.latest_revision == second.revision
    assert summary.published_revision == 1
    assert summary.call_count == 1
    assert summary.updated_at == second.inserted_at

    assert {:ok, {^listed_tenant, [], 1}} =
             AdminStore.list_definitions(Repo, tenant.key, 25, 25)

    assert {:error, :tenant_not_found} =
             AdminStore.list_definitions(Repo, "BBBBBBBBBBBBBBBB", 25, 0)
  end

  defp sequence(values) do
    key = {__MODULE__, make_ref()}
    Process.put(key, values)

    fn ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  defp definition_input(name) do
    %{
      schema_version: "20260915.01",
      name: name,
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
