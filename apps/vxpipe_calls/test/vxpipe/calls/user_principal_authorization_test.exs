defmodule Vxpipe.Calls.UserPrincipalAuthorizationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    CallDirectorySummary,
    CallReadAccess,
    CallSpecAuthoring,
    CallSpecSummary,
    InstallationOperator,
    OperatorAdministration,
    OperatorCallSpecs,
    OperatorPhoneNumbers,
    OperatorServiceBindings,
    OperatorTelephonyApplications,
    ProviderCatalog,
    Tenant,
    TenantPage,
    UserAuthorization
  }

  alias Vxpipe.Calls.TestAdminRepository
  alias Vxpipe.Calls.TestOperatorCredentialRepository
  alias Vxpipe.Calls.TestOperatorCredentialValidator
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  test "tenant operation authorization rejects unregistered grant strings" do
    principal = base_principal(%{
      grants: MapSet.new(["unknown.write"]),
      assigned_tenants: %{@tenant => :read_write}
    })

    assert {:error, :forbidden} =
             UserAuthorization.authorize_tenant_scoped(principal, "unknown.write", @tenant, true)
  end

  test "tenant directory includes only assignments with an effective read" do
    principal = base_principal(%{
      grants: MapSet.new(["calls.write", "tenant_services.read"]),
      assigned_tenants: %{@tenant => :read_write, @other => :read}
    })

    assert {:ok, keys} = UserAuthorization.listable_assigned_keys(principal)
    assert keys == [@tenant, @other]

    write_only = %{principal | grants: MapSet.new(["calls.write"])}
    assert {:ok, [@tenant]} = UserAuthorization.listable_assigned_keys(write_only)
  end

  defp base_principal(overrides) do
    base = %{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: :member,
      grants: MapSet.new(),
      assigned_tenants: %{},
      all_tenant_actions: MapSet.new()
    }

    struct!(UserPrincipal, Map.merge(base, overrides))
  end

  defp superadmin_principal do
    base_principal(%{
      account_kind: :superadmin,
      grants:
        MapSet.new([
          "tenants.read",
          "calls.read",
          "calls.write",
          "call_specs.read",
          "call_specs.write",
          "call_specs.use_platform_services",
          "platform_services.read",
          "platform_services.write",
          "tenant_services.read",
          "tenant_services.write",
          "tenant_api_keys.read",
          "tenant_api_keys.write"
        ]),
      all_tenant_actions:
        MapSet.new(["calls.read", "calls.write", "call_specs.read", "call_specs.write",
          "tenant_services.read", "tenant_services.write", "tenant_api_keys.read", "tenant_api_keys.write"])
    })
  end

  defp member_principal(tenant, level \\ :read_write) do
    base_principal(%{
      grants: MapSet.new(["calls.read", "calls.write", "call_specs.read", "call_specs.write"]),
      assigned_tenants: %{tenant => level},
      all_tenant_actions: MapSet.new()
    })
  end

  defp tenant_fixture(key) do
    %Tenant{key: key, name: "Tenant #{key}", inserted_at: ~U[2026-09-17 01:00:00Z]}
  end

  test "tenant list scopes assigned tenants before pagination" do
    tenants = [tenant_fixture(@tenant), tenant_fixture(@other)]

    scoped =
      start_supervised!({TestAdminRepository, {:ok, {[Enum.at(tenants, 0)], 1}}},
        id: :scoped_list
      )

    all = start_supervised!({TestAdminRepository, {:ok, {tenants, 2}}}, id: :all_list)

    member =
      @tenant
      |> member_principal()
      |> Map.put(:grants, MapSet.put(member_principal(@tenant).grants, "tenants.read"))

    assert {:ok, %TenantPage{tenants: [%Tenant{key: @tenant}], total: 1, total_pages: 1}} =
             Vxpipe.Calls.list_operator_tenants(member,
               admin_repository: TestAdminRepository.admin_repository(scoped)
             )

    assert_received {:admin_repository_list_tenants_scoped, {:keys, [@tenant]}, 25, 0}

    assert {:ok, %TenantPage{total: 2}} =
             Vxpipe.Calls.list_operator_tenants(superadmin_principal(),
               admin_repository: TestAdminRepository.admin_repository(all)
             )

    assert_received {:admin_repository_list_tenants, 25, 0}

    denied = base_principal(%{assigned_tenants: %{@tenant => :read}})

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_tenants(denied,
               admin_repository: TestAdminRepository.admin_repository(all)
             )

    # Unknown tenant keys in the assigned set never reach storage as a page.
    empty_member =
      base_principal(%{grants: MapSet.new(["tenants.read"]), assigned_tenants: %{}})

    assert {:ok, %TenantPage{tenants: [], total: 0, total_pages: 0}} =
             OperatorAdministration.list_tenants(empty_member, [])

    # InstallationOperator path is preserved.
    assert {:ok, %TenantPage{total: 2}} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               admin_repository: TestAdminRepository.admin_repository(all)
             )
  end

  test "tenant directory supports all-tenant service and key roles and empty assignments" do
    repository = start_supervised!({TestAdminRepository, {:ok, {[tenant_fixture(@tenant)], 1}}})
    options = [admin_repository: TestAdminRepository.admin_repository(repository)]

    for action <- ["tenant_services.read", "tenant_api_keys.read"] do
      principal = base_principal(%{grants: MapSet.new([action]), all_tenant_actions: MapSet.new([action])})
      assert {:ok, %TenantPage{total: 1}} = OperatorAdministration.list_tenants(principal, options)
      assert_received {:admin_repository_list_tenants, 25, 0}
    end

    unassigned = base_principal(%{grants: MapSet.new(["calls.read"])})
    assert {:ok, %TenantPage{tenants: [], total: 0}} = OperatorAdministration.list_tenants(unassigned, [])
    refute_received {:admin_repository_list_tenants, _, _}

    stale_scope = base_principal(%{all_tenant_actions: MapSet.new(["calls.read"])})
    assert {:error, :forbidden} = OperatorAdministration.list_tenants(stale_scope, options)
  end

  test "call listing enforces actual resource tenant for user principals" do
    tenant = tenant_fixture(@tenant)

    calls = [
      %CallDirectorySummary{
        id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
        call_spec_id: "spec",
        call_spec_name: "Spec",
        call_spec_revision: 1,
        state: :running,
        created_at: ~U[2026-09-17 02:20:00Z],
        started_at: nil,
        ended_at: nil,
        terminal_reason: nil,
        archive_state: :unconfirmed
      }
    ]

    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, [], false, calls, 1}}})

    member = member_principal(@tenant, :read)

    assert {:ok, page} =
             Vxpipe.Calls.list_operator_calls(member, @tenant,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert page.total == 1

    foreign = member_principal(@other, :read)

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_calls(foreign, @tenant,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    # Malformed tenant keys are rejected before repository access.
    assert {:error, :invalid_tenant_key} =
             Vxpipe.Calls.list_operator_calls(member, "bad",
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    # A repository row for another tenant is rejected at the owning boundary.
    crossed =
      start_supervised!(
        {TestAdminRepository, {:ok, {tenant_fixture(@other), [], false, calls, 1}}},
        id: :crossed_calls
      )

    assert {:error, :call_directory_unavailable} =
             Vxpipe.Calls.list_operator_calls(member, @tenant,
               admin_repository: TestAdminRepository.admin_repository(crossed)
             )
  end

  test "call spec listing and fetch enforce call_specs.read on the resolved tenant" do
    tenant = tenant_fixture(@tenant)

    specs = [
      %CallSpecSummary{
        id: "s",
        name: "S",
        latest_revision: 1,
        published_revision: nil,
        call_count: 0,
        updated_at: ~U[2026-09-17 03:00:00Z]
      }
    ]

    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, specs, 1}}})
    opts = [admin_repository: TestAdminRepository.admin_repository(repository)]

    reader = member_principal(@tenant, :read)

    assert {:ok, _} = Vxpipe.Calls.list_operator_call_specs(reader, @tenant, opts)

    no_grant =
      base_principal(%{grants: MapSet.new(["calls.read"]), assigned_tenants: %{@tenant => :read}})

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_call_specs(no_grant, @tenant, opts)

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_call_specs(reader, @other, opts)

    assert {:error, :invalid_tenant_key} =
             Vxpipe.Calls.list_operator_call_specs(reader, "bad", opts)

    crossed =
      start_supervised!({TestAdminRepository, {:ok, {tenant_fixture(@other), specs, 1}}},
        id: :crossed_specs
      )

    assert {:error, :call_spec_page_unavailable} =
             Vxpipe.Calls.list_operator_call_specs(reader, @tenant,
               admin_repository: TestAdminRepository.admin_repository(crossed)
             )

    # Unknown spec IDs are rejected without leaking foreign rows.
    assert {:error, :forbidden} =
             OperatorCallSpecs.fetch(
               base_principal(%{grants: MapSet.new(), assigned_tenants: %{}}),
               @tenant,
               "s",
               opts
             )
  end

  test "fetch_call_context requires calls.read and pins call to tenant" do
    tenant = tenant_fixture(@tenant)

    call = %CallDirectorySummary{
      id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
      call_spec_id: "spec",
      call_spec_name: "Spec",
      call_spec_revision: 1,
      state: :running,
      created_at: ~U[2026-09-17 02:20:00Z],
      started_at: nil,
      ended_at: nil,
      terminal_reason: nil,
      archive_state: :unconfirmed
    }

    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, call}}})
    opts = [admin_repository: TestAdminRepository.admin_repository(repository)]
    member = member_principal(@tenant, :read)

    assert {:ok, context} =
             OperatorAdministration.fetch_call_context(member, @tenant, call.id, opts)

    assert context.call.id == call.id

    assert {:error, :forbidden} =
             OperatorAdministration.fetch_call_context(
               member_principal(@other, :read),
               @tenant,
               call.id,
               opts
             )

    assert {:error, :forbidden} =
             OperatorAdministration.fetch_call_context(
               base_principal(%{grants: MapSet.new(), assigned_tenants: %{@tenant => :read}}),
               @tenant,
               call.id,
               opts
             )
  end

  test "user call access pins tenant reads for downstream inspection boundaries" do
    member = member_principal(@tenant, :read)

    assert {:ok, access} = Vxpipe.Calls.user_call_access(member, @tenant)
    assert {:ok, @tenant} = CallReadAccess.tenant_key(access)

    assert {:error, :forbidden} =
             Vxpipe.Calls.user_call_access(member_principal(@other, :read), @tenant)

    assert {:error, :forbidden} =
             Vxpipe.Calls.user_call_access(base_principal(%{grants: MapSet.new()}), @tenant)

    assert {:error, :invalid_tenant_key} = Vxpipe.Calls.user_call_access(member, "bad")

    # Operator access is unchanged.
    assert {:ok, _} = Vxpipe.Calls.operator_call_access(InstallationOperator.authority(), @tenant)
  end

  defp tenant_manager_principal(tenant, extra_grants \\ []) do
    grants =
      MapSet.new([
        "calls.read",
        "calls.write",
        "call_specs.read",
        "call_specs.write",
        "tenant_services.read",
        "tenant_services.write",
        "tenant_api_keys.read",
        "tenant_api_keys.write" | extra_grants
      ])

    base_principal(%{
      grants: grants,
      assigned_tenants: %{tenant => :read_write},
      all_tenant_actions: MapSet.new()
    })
  end

  defp tenant_member_read_principal(tenant) do
    base_principal(%{
      grants: MapSet.new(["calls.read", "call_specs.read"]),
      assigned_tenants: %{tenant => :read},
      all_tenant_actions: MapSet.new()
    })
  end

  test "service reads require tenant_services.read and reject foreign tenants" do
    tenant = tenant_fixture(@tenant)
    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, [], [], false}}})
    opts = [admin_repository: TestAdminRepository.admin_repository(repository)]

    allowed = tenant_manager_principal(@tenant)

    assert {:ok, _} = Vxpipe.Calls.list_operator_services(allowed, @tenant, opts)

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_services(base_principal(%{}), @tenant, opts)

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_services(allowed, @other, opts)

    assert {:error, :invalid_tenant_key} =
             Vxpipe.Calls.list_operator_services(allowed, "bad", opts)

    foreign_repo =
      start_supervised!({TestAdminRepository, {:ok, {tenant_fixture(@other), [], [], false}}},
        id: :foreign_services
      )

    assert {:error, :service_directory_unavailable} =
             Vxpipe.Calls.list_operator_services(allowed, @tenant,
               admin_repository: TestAdminRepository.admin_repository(foreign_repo)
             )

    # Installation-wide admins keep cross-tenant visibility.
    assert {:ok, _} =
             Vxpipe.Calls.list_operator_services(superadmin_principal(), @tenant, opts)
  end

  test "telephony application reads/writes enforce tenant_services grants" do
    reader =
      base_principal(%{
        grants: MapSet.new(["tenant_services.read"]),
        assigned_tenants: %{@tenant => :read},
        all_tenant_actions: MapSet.new()
      })

    writer = tenant_manager_principal(@tenant)

    denied = base_principal(%{grants: MapSet.new()})

    assert {:error, :forbidden} = OperatorTelephonyApplications.list(denied, @tenant, [])
    assert {:error, :forbidden} = OperatorTelephonyApplications.list(reader, @other, [])

    assert {:error, :forbidden} =
             OperatorTelephonyApplications.create(denied, @tenant, %{"name" => "x"}, [])

    assert {:error, :invalid_tenant_key} = OperatorTelephonyApplications.list(reader, "bad", [])

    assert {:error, _} = OperatorTelephonyApplications.list(reader, @tenant, [])

    assert {:error, :invalid_telephony_service} =
             OperatorTelephonyApplications.create(writer, @tenant, %{}, [])
  end

  test "phone numbers require call_specs.write and provider catalog requires call_specs.read" do
    service_manager = base_principal(%{grants: MapSet.new(["tenant_services.read"])})
    denied = base_principal(%{grants: MapSet.new()})

    assert {:error, :forbidden} =
             OperatorPhoneNumbers.list(denied, @tenant, "svc", %{search: "", page: nil}, [])

    assert {:error, :forbidden} =
             OperatorPhoneNumbers.list(
               service_manager,
               @tenant,
               "svc",
               %{search: "", page: nil},
               []
             )

    assert {:error, :invalid_tenant_key} =
             OperatorPhoneNumbers.list(
               service_manager,
               "bad",
               "svc",
               %{search: "", page: nil},
               []
             )

    assert {:error, :forbidden} = ProviderCatalog.providers(denied, @tenant, "text_to_speech", [])

    assert {:error, :forbidden} =
             ProviderCatalog.providers(service_manager, @tenant, "text_to_speech", [])

    assert {:error, :invalid_tenant_key} =
             ProviderCatalog.providers(service_manager, "bad", "text_to_speech", [])
  end

  test "service bindings scope platform and tenant separately" do
    platform_reader = base_principal(%{grants: MapSet.new(["platform_services.read"])})

    tenant_reader =
      base_principal(%{
        grants: MapSet.new(["tenant_services.read"]),
        assigned_tenants: %{@tenant => :read},
        all_tenant_actions: MapSet.new()
      })

    denied = base_principal(%{grants: MapSet.new()})

    assert {:error, :forbidden} = OperatorServiceBindings.list(denied, :platform, [])
    assert {:error, :forbidden} = OperatorServiceBindings.list(denied, @tenant, [])
    assert {:error, :forbidden} = OperatorServiceBindings.list(tenant_reader, :platform, [])
    assert {:error, :forbidden} = OperatorServiceBindings.list(tenant_reader, @other, [])
    assert {:error, :forbidden} = OperatorServiceBindings.list(platform_reader, @tenant, [])
  end

  test "credential test requires read; create/update/delete require write" do
    validator = TestOperatorCredentialValidator.validator(self(), :ok)

    repo =
      TestOperatorCredentialRepository.repository(self(), {:error, :provider_credential_conflict})

    reader =
      base_principal(%{
        grants: MapSet.new(["tenant_api_keys.read"]),
        assigned_tenants: %{@tenant => :read},
        all_tenant_actions: MapSet.new()
      })

    writer = tenant_manager_principal(@tenant)

    denied = base_principal(%{grants: MapSet.new()})

    assert :ok =
             OperatorAdministration.validate_credential(
               reader,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               %{
                 "api_key" => "private"
               },
               provider_credential_validator: validator
             )

    assert {:error, :forbidden} =
             OperatorAdministration.validate_credential(
               denied,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               %{
                 "api_key" => "private"
               },
               provider_credential_validator: validator
             )

    assert {:error, :forbidden} =
             OperatorAdministration.create_credential(
               reader,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               %{
                 "api_key" => "private"
               },
               provider_credential_repository: repo
             )

    assert {:error, :provider_credential_conflict} =
             OperatorAdministration.create_credential(
               writer,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               %{
                 "api_key" => "private"
               },
               provider_credential_repository: repo
             )

    platform_writer =
      base_principal(%{grants: MapSet.new(["platform_services.read", "platform_services.write"])})

    assert {:error, :forbidden} =
             OperatorAdministration.create_credential(
               writer,
               :platform,
               "google",
               "shared",
               "api_key",
               %{
                 "api_key" => "private"
               },
               provider_credential_repository: repo
             )

    assert {:error, _} =
             OperatorAdministration.create_credential(
               platform_writer,
               :platform,
               "google",
               "shared",
               "api_key",
               %{
                 "api_key" => "private"
               },
               provider_credential_repository: repo
             )
  end

  test "assigned member without tenants.read lists only assigned tenants" do
    tenants = [tenant_fixture(@tenant), tenant_fixture(@other)]

    scoped =
      start_supervised!({TestAdminRepository, {:ok, {[Enum.at(tenants, 0)], 1}}},
        id: :assigned_member_list
      )

    member = member_principal(@tenant)

    assert {:ok, %TenantPage{tenants: [%Tenant{key: @tenant}], total: 1, total_pages: 1}} =
             Vxpipe.Calls.list_operator_tenants(member,
               admin_repository: TestAdminRepository.admin_repository(scoped)
             )

    assert_received {:admin_repository_list_tenants_scoped, {:keys, [@tenant]}, 25, 0}

    empty = base_principal(%{grants: MapSet.new(["calls.read"]), assigned_tenants: %{}})

    assert {:ok, %TenantPage{tenants: [], total: 0}} =
             Vxpipe.Calls.list_operator_tenants(empty,
               admin_repository: TestAdminRepository.admin_repository(scoped)
             )

    no_useful =
      base_principal(%{grants: MapSet.new(), assigned_tenants: %{@tenant => :read}})

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_tenants(no_useful,
               admin_repository: TestAdminRepository.admin_repository(scoped)
             )

    crossed =
      start_supervised!({TestAdminRepository, {:ok, {[tenant_fixture(@other)], 1}}},
        id: :crossed_assigned_list
      )

    assert {:error, :tenant_page_unavailable} =
             Vxpipe.Calls.list_operator_tenants(member,
               admin_repository: TestAdminRepository.admin_repository(crossed)
             )
  end

  test "authoring requires call_specs.write and preserves platform modifier" do
    tenant_key = @tenant

    writer =
      base_principal(%{
        grants: MapSet.new(["call_specs.read", "call_specs.write"]),
        assigned_tenants: %{tenant_key => :read_write},
        all_tenant_actions: MapSet.new()
      })

    assert {:error, _reason} = CallSpecAuthoring.save(writer, tenant_key, %{}, [])

    reader =
      base_principal(%{
        grants: MapSet.new(["call_specs.read"]),
        assigned_tenants: %{tenant_key => :read},
        all_tenant_actions: MapSet.new()
      })

    assert {:error, :forbidden} = CallSpecAuthoring.save(reader, tenant_key, %{}, [])
    assert {:error, :forbidden} = CallSpecAuthoring.publish(reader, tenant_key, "spec", 1, [])

    foreign_writer =
      base_principal(%{
        grants: MapSet.new(["call_specs.read", "call_specs.write"]),
        assigned_tenants: %{@other => :read_write},
        all_tenant_actions: MapSet.new()
      })

    assert {:error, :forbidden} = CallSpecAuthoring.save(foreign_writer, tenant_key, %{}, [])

    # Platform-allowed authors drop the tenant restriction; others keep it.
    privileged =
      base_principal(%{
        grants:
          MapSet.new([
            "call_specs.read",
            "call_specs.write",
            "call_specs.use_platform_services"
          ]),
        assigned_tenants: %{tenant_key => :read_write},
        all_tenant_actions: MapSet.new()
      })

    assert Vxpipe.Calls.UserAuthorization.platform_authoring_allowed?(privileged)
    refute Vxpipe.Calls.UserAuthorization.platform_authoring_allowed?(writer)
  end

  test "assigned tenant manager lists services only for assigned tenant" do
    tenant = tenant_fixture(@tenant)

    credential = %Vxpipe.Calls.ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: @tenant,
      provider: "deepgram",
      name: "deepgram",
      auth_kind: "api_key",
      secret_hints: %{"api_key" => "1234"}
    }

    repository =
      start_supervised!({TestAdminRepository, {:ok, {tenant, [credential], [], false}}})

    opts = [admin_repository: TestAdminRepository.admin_repository(repository)]
    manager = tenant_manager_principal(@tenant)

    assert {:ok, directory} = Vxpipe.Calls.list_operator_services(manager, @tenant, opts)
    assert directory.tenant.key == @tenant
    assert [%Vxpipe.Calls.ProviderCredential{id: _}] = directory.credentials
    # Metadata-only projection: no payload, no secret values.
    refute Map.has_key?(hd(directory.credentials), :payload)
    refute inspect(directory) =~ "private"

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_services(manager, @other, opts)

    assert {:error, :invalid_tenant_key} =
             Vxpipe.Calls.list_operator_services(manager, "bad", opts)

    member = tenant_member_read_principal(@tenant)

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_operator_services(member, @tenant, opts)
  end

  test "service and API-key inventories stay separate for custom roles" do
    tenant = tenant_fixture(@tenant)
    credential = %Vxpipe.Calls.ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: @tenant,
      provider: "deepgram",
      name: "deepgram",
      auth_kind: "api_key",
      secret_hints: %{"api_key" => "1234"}
    }

    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, [credential], [], false}}})
    opts = [admin_repository: TestAdminRepository.admin_repository(repository)]
    service_reader = base_principal(%{
      grants: MapSet.new(["tenant_services.read"]),
      assigned_tenants: %{@tenant => :read}
    })
    key_reader = base_principal(%{
      grants: MapSet.new(["tenant_api_keys.read"]),
      assigned_tenants: %{@tenant => :read}
    })

    assert {:ok, service_directory} = Vxpipe.Calls.list_operator_services(service_reader, @tenant, opts)
    assert service_directory.credentials == []
    assert {:ok, key_directory} = Vxpipe.Calls.list_operator_services(key_reader, @tenant, opts)
    assert [%Vxpipe.Calls.ProviderCredential{}] = key_directory.credentials
    assert key_directory.telephony_services == []
  end

  test "assigned tenant manager manages telephony applications within assignment" do
    manager = tenant_manager_principal(@tenant)
    member = tenant_member_read_principal(@tenant)

    assert {:error, :forbidden} = OperatorTelephonyApplications.list(member, @tenant, [])
    assert {:error, :forbidden} = OperatorTelephonyApplications.list(manager, @other, [])
    assert {:error, :invalid_tenant_key} = OperatorTelephonyApplications.list(manager, "bad", [])

    assert {:error, :forbidden} =
             OperatorTelephonyApplications.create(member, @tenant, %{"name" => "app"}, [])

    assert {:error, :forbidden} =
             OperatorTelephonyApplications.create(manager, @other, %{"name" => "app"}, [])
  end

  test "assigned tenant manager lists tenant bindings but never platform" do
    manager = tenant_manager_principal(@tenant)
    member = tenant_member_read_principal(@tenant)

    assert {:error, :forbidden} = OperatorServiceBindings.list(member, @tenant, [])
    assert {:error, :forbidden} = OperatorServiceBindings.list(manager, :platform, [])
    assert {:error, :forbidden} = OperatorServiceBindings.list(manager, @other, [])
  end

  test "assigned tenant manager manages tenant credentials, denied cross-tenant and platform" do
    validator = TestOperatorCredentialValidator.validator(self(), :ok)

    repo =
      TestOperatorCredentialRepository.repository(self(), {:error, :provider_credential_conflict})

    manager = tenant_manager_principal(@tenant)
    member = tenant_member_read_principal(@tenant)
    payload = %{"api_key" => "private"}

    assert :ok =
             OperatorAdministration.validate_credential(
               manager,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               payload,
               provider_credential_validator: validator
             )

    assert :ok =
             OperatorAdministration.validate_credential(
               manager,
               {:tenant, @tenant},
               "deepgram",
               "deepgram",
               "api_key",
               payload,
               provider_credential_validator: validator
             )

    assert {:error, :forbidden} =
             OperatorAdministration.validate_credential(
               manager,
               @other,
               "deepgram",
               "deepgram",
               "api_key",
               payload,
               provider_credential_validator: validator
             )

    assert {:error, :forbidden} =
             OperatorAdministration.validate_credential(
               manager,
               :platform,
               "google",
               "shared",
               "api_key",
               payload,
               provider_credential_validator: validator
             )

    assert {:error, :forbidden} =
             OperatorAdministration.validate_credential(
               member,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               payload,
               provider_credential_validator: validator
             )

    assert {:error, :provider_credential_conflict} =
             OperatorAdministration.create_credential(
               manager,
               @tenant,
               "deepgram",
               "deepgram",
               "api_key",
               payload,
               provider_credential_repository: repo
             )

    assert {:error, :forbidden} =
             OperatorAdministration.create_credential(
               manager,
               @other,
               "deepgram",
               "deepgram",
               "api_key",
               payload,
               provider_credential_repository: repo
             )

    assert {:error, :forbidden} =
             OperatorAdministration.create_credential(
               manager,
               :platform,
               "google",
               "shared",
               "api_key",
               payload,
               provider_credential_repository: repo
             )

    assert {:error, :forbidden} =
             OperatorAdministration.delete_credential(manager, @other, "cred-id", [])

    assert {:error, :forbidden} =
             OperatorAdministration.delete_credential(manager, :platform, "cred-id", [])

    assert {:error, :forbidden} =
             OperatorAdministration.delete_credential(member, @tenant, "cred-id", [])
  end

  test "read-only tenant member keeps calls/specs read-only" do
    tenant = tenant_fixture(@tenant)
    member = tenant_member_read_principal(@tenant)

    calls_repo =
      start_supervised!({TestAdminRepository, {:ok, {tenant, [], false, [], 0}}},
        id: :member_calls_repo
      )

    specs_repo =
      start_supervised!({TestAdminRepository, {:ok, {tenant, [], 0}}}, id: :member_specs_repo)

    assert {:ok, _} =
             Vxpipe.Calls.list_operator_calls(member, @tenant,
               admin_repository: TestAdminRepository.admin_repository(calls_repo)
             )

    assert {:ok, _} =
             Vxpipe.Calls.list_operator_call_specs(member, @tenant,
               admin_repository: TestAdminRepository.admin_repository(specs_repo)
             )

    assert {:error, :forbidden} = CallSpecAuthoring.save(member, @tenant, %{}, [])
  end
end
