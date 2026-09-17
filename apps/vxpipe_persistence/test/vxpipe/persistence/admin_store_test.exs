defmodule Vxpipe.Persistence.AdminStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{Administration, Definitions, InstallationOperator}
  alias Vxpipe.Persistence.{AdminStore, CredentialStore, DefinitionStore, Repo}

  alias Vxpipe.Persistence.Schema.{
    Call,
    CallDefinition,
    CallDetailsPublication,
    DefinitionRevision,
    Tenant
  }

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

    assert {:error, :repository_unavailable} =
             AdminStore.list_calls(TestUnavailableAdminRepo, "AAAAAAAAAAAAAAAA", nil, 25, 0)
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

  test "lists tenant calls across immutable definition revisions with exact filtering" do
    tenant = insert_tenant("AAAAAAAAAAAAAAAA", "Example tenant")
    other_tenant = insert_tenant("BBBBBBBBBBBBBBBB", "Other tenant")

    definition = insert_definition(tenant, "delivery-rescheduling")
    old_revision = insert_revision(definition, 1, "Original delivery name")
    current_revision = insert_revision(definition, 2, "Delivery rescheduling")
    other_definition = insert_definition(tenant, "appointment-reminders")
    reminder_revision = insert_revision(other_definition, 1, "Appointment reminders")
    foreign_definition = insert_definition(other_tenant, "foreign-definition")
    foreign_revision = insert_revision(foreign_definition, 1, "Foreign definition")

    older =
      insert_call(
        tenant,
        old_revision,
        "11111111-1111-4111-8111-111111111111",
        :ended,
        ~U[2026-09-17 03:00:00Z]
      )

    newer =
      insert_call(
        tenant,
        current_revision,
        "22222222-2222-4222-8222-222222222222",
        :running,
        ~U[2026-09-17 04:00:00Z]
      )

    reminder =
      insert_call(
        tenant,
        reminder_revision,
        "33333333-3333-4333-8333-333333333333",
        :failed,
        ~U[2026-09-17 02:00:00Z]
      )

    _foreign =
      insert_call(
        other_tenant,
        foreign_revision,
        "44444444-4444-4444-8444-444444444444",
        :ended,
        ~U[2026-09-17 05:00:00Z]
      )

    attach_publication(older, :complete, "complete-publication")
    attach_publication(reminder, :incomplete, "incomplete-publication")

    assert {:ok, {listed_tenant, definitions, false, calls, 2}} =
             AdminStore.list_calls(Repo, tenant.key, definition.public_id, 25, 0)

    assert listed_tenant.key == tenant.key

    assert Enum.map(definitions, &{&1.id, &1.name}) == [
             {"appointment-reminders", "Appointment reminders"},
             {"delivery-rescheduling", "Delivery rescheduling"}
           ]

    assert Enum.map(calls, & &1.id) == [newer.public_id, older.public_id]
    assert Enum.map(calls, & &1.definition_revision) == [2, 1]

    assert Enum.map(calls, & &1.definition_name) == [
             "Delivery rescheduling",
             "Original delivery name"
           ]

    assert Enum.map(calls, & &1.archive_state) == [:unconfirmed, :complete]

    assert {:ok, {^listed_tenant, _definitions, false, all_calls, 3}} =
             AdminStore.list_calls(Repo, tenant.key, nil, 25, 0)

    assert Enum.map(all_calls, & &1.id) == [newer.public_id, older.public_id, reminder.public_id]
    assert List.last(all_calls).archive_state == :incomplete

    assert {:ok, {^listed_tenant, _definitions, false, [], 3}} =
             AdminStore.list_calls(Repo, tenant.key, nil, 25, 25)

    assert {:error, :definition_not_found} =
             AdminStore.list_calls(Repo, tenant.key, foreign_definition.public_id, 25, 0)

    assert {:error, :tenant_not_found} =
             AdminStore.list_calls(Repo, "CCCCCCCCCCCCCCCC", nil, 25, 0)
  end

  test "bounds definition filter options and reports truncation without breaking a deep link" do
    tenant = insert_tenant("AAAAAAAAAAAAAAAA", "Example tenant")

    for number <- 1..101 do
      public_id = "definition-#{String.pad_leading(Integer.to_string(number), 3, "0")}"
      definition = insert_definition(tenant, public_id)
      insert_revision(definition, 1, "Definition #{number}")
    end

    assert {:ok, {_tenant, definitions, true, [], 0}} =
             AdminStore.list_calls(Repo, tenant.key, nil, 25, 0)

    assert length(definitions) == 100
    refute Enum.any?(definitions, &(&1.id == "definition-099"))

    assert {:ok, {_tenant, selected_definitions, true, [], 0}} =
             AdminStore.list_calls(Repo, tenant.key, "definition-099", 25, 0)

    assert Enum.any?(selected_definitions, &(&1.id == "definition-099"))
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

  defp insert_tenant(key, name) do
    %Tenant{}
    |> Tenant.changeset(%{key: key, name: name})
    |> Repo.insert!()
  end

  defp insert_definition(tenant, public_id) do
    %CallDefinition{}
    |> CallDefinition.changeset(%{tenant_id: tenant.id, public_id: public_id})
    |> Repo.insert!()
  end

  defp insert_revision(definition, revision, name) do
    %DefinitionRevision{}
    |> DefinitionRevision.changeset(%{
      call_definition_id: definition.id,
      revision: revision,
      schema_version: "20260915.01",
      source: %{"name" => name},
      source_digest: String.duplicate(Integer.to_string(revision), 64),
      compiled_metadata: %{},
      validation_errors: []
    })
    |> Repo.insert!()
  end

  defp insert_call(tenant, revision, public_id, state, created_at) do
    ended_at = if state in [:ended, :failed], do: DateTime.add(created_at, 60, :second)
    started_at = if state in [:running, :ended], do: DateTime.add(created_at, 1, :second)
    terminal_reason = if state == :failed, do: :session_start_failed

    %Call{}
    |> Call.changeset(%{
      public_id: public_id,
      participant_routes: %{},
      entry_caller: "caller",
      entry_receiver: "assistant",
      initial_variables: %{},
      resolved_plan: :erlang.term_to_binary(%{}),
      plan_digest: :crypto.strong_rand_bytes(32),
      state: state,
      room_id: Ecto.UUID.generate(),
      created_at: created_at,
      started_at: started_at,
      ended_at: ended_at,
      terminal_reason: terminal_reason,
      tenant_id: tenant.id,
      definition_revision_id: revision.id
    })
    |> Repo.insert!()
  end

  defp attach_publication(call, completeness, public_id) do
    publication =
      %CallDetailsPublication{
        public_id: public_id,
        schema_version: "20260912.01",
        source_digest: :crypto.strong_rand_bytes(32),
        recorded_at: call.created_at,
        filename: "#{public_id}.json",
        completeness: completeness,
        checksum: :crypto.strong_rand_bytes(32),
        contents: "{}",
        status: :published,
        object_key: "calls/#{call.public_id}/#{public_id}.json",
        object_reference: %{"etag" => public_id},
        published_at: DateTime.add(call.created_at, 120, :second),
        call_id: call.id
      }
      |> Repo.insert!()

    call
    |> Call.latest_details_publication_changeset(publication.id)
    |> Repo.update!()
  end
end
