defmodule Vxpipe.Calls.OperatorAdministrationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    CallDirectoryPage,
    CallDirectorySummary,
    CallSpecFilter,
    CallSpecPage,
    CallSpecSummary,
    InstallationOperator,
    Principal,
    ProviderCredential,
    ServiceDirectory,
    Tenant,
    TenantPage,
    TelephonyService
  }

  alias Vxpipe.Calls.{
    TestAdminRepository,
    TestOperatorCredentialRepository,
    TestOperatorCredentialValidator
  }

  test "lists one bounded deterministic tenant page for installation operator authority" do
    tenants = [
      %Tenant{key: "BBBBBBBBBBBBBBBB", name: "Second", inserted_at: ~U[2026-09-17 02:00:00Z]},
      %Tenant{key: "AAAAAAAAAAAAAAAA", name: "First", inserted_at: ~U[2026-09-17 01:00:00Z]}
    ]

    repository = start_supervised!({TestAdminRepository, {:ok, {tenants, 7}}})

    assert {:ok,
            %TenantPage{
              tenants: ^tenants,
              page: 2,
              page_size: 2,
              total: 7,
              total_pages: 4
            }} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               page: 2,
               limit: 2,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert_received {:admin_repository_list_tenants, 2, 2}
  end

  test "rejects tenant API identity and invalid or unbounded pages before repository access" do
    repository = start_supervised!({TestAdminRepository, {:ok, {[], 0}}})
    options = [admin_repository: TestAdminRepository.admin_repository(repository)]

    principal = %Principal{
      tenant_key: "AAAAAAAAAAAAAAAA",
      api_key_id: "key",
      scopes: MapSet.new([:admin])
    }

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.list_operator_tenants(principal, options)

    assert {:error, :invalid_tenant_page_request} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               page: 0,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert {:error, :invalid_tenant_page_request} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               limit: 101,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    refute_received {:admin_repository_list_tenants, _, _}
  end

  test "keeps empty data distinct from repository failure" do
    empty_repository = start_supervised!({TestAdminRepository, {:ok, {[], 0}}}, id: :empty)

    failed_repository =
      start_supervised!({TestAdminRepository, {:error, :database_unavailable}}, id: :failed)

    assert {:ok, %TenantPage{tenants: [], total: 0, total_pages: 0}} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               admin_repository: TestAdminRepository.admin_repository(empty_repository)
             )

    assert {:error, :database_unavailable} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               admin_repository: TestAdminRepository.admin_repository(failed_repository)
             )
  end

  test "rejects a page beyond the available tenant range" do
    repository = start_supervised!({TestAdminRepository, {:ok, {[], 7}}})

    assert {:error, :tenant_page_out_of_range} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               page: 2,
               limit: 25,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )
  end

  test "lists one tenant's bounded call spec summaries" do
    tenant = %Tenant{
      key: "AAAAAAAAAAAAAAAA",
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    call_specs = [
      %CallSpecSummary{
        id: "delivery-rescheduling",
        name: "Delivery rescheduling",
        latest_revision: 4,
        published_revision: 3,
        call_count: 5,
        updated_at: ~U[2026-09-17 03:00:00Z]
      }
    ]

    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, call_specs, 3}}})

    assert {:ok,
            %CallSpecPage{
              tenant: ^tenant,
              call_specs: ^call_specs,
              page: 2,
              page_size: 2,
              total: 3,
              total_pages: 2
            }} =
             Vxpipe.Calls.list_operator_call_specs(
               InstallationOperator.authority(),
               tenant.key,
               page: 2,
               limit: 2,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert_received {:admin_repository_list_call_specs, "AAAAAAAAAAAAAAAA", 2, 2}
  end

  test "keeps missing call spec tenants and unavailable storage distinct" do
    missing = start_supervised!({TestAdminRepository, {:error, :tenant_not_found}}, id: :missing)

    failed =
      start_supervised!({TestAdminRepository, {:error, :database_unavailable}}, id: :failed)

    assert {:error, :tenant_not_found} =
             Vxpipe.Calls.list_operator_call_specs(
               InstallationOperator.authority(),
               "missing",
               admin_repository: TestAdminRepository.admin_repository(missing)
             )

    assert {:error, :database_unavailable} =
             Vxpipe.Calls.list_operator_call_specs(
               InstallationOperator.authority(),
               "AAAAAAAAAAAAAAAA",
               admin_repository: TestAdminRepository.admin_repository(failed)
             )

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.list_operator_call_specs(
               %Principal{
                 tenant_key: "AAAAAAAAAAAAAAAA",
                 api_key_id: "key",
                 scopes: MapSet.new()
               },
               "AAAAAAAAAAAAAAAA",
               admin_repository: TestAdminRepository.admin_repository(failed)
             )
  end

  test "lists one tenant's calls with an exact optional call spec filter" do
    tenant = %Tenant{
      key: "AAAAAAAAAAAAAAAA",
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    call_specs = [
      %CallSpecFilter{id: "delivery-rescheduling", name: "Delivery rescheduling"}
    ]

    calls = [
      %CallDirectorySummary{
        id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
        call_spec_id: "delivery-rescheduling",
        call_spec_name: "Delivery rescheduling",
        call_spec_revision: 3,
        state: :running,
        created_at: ~U[2026-09-17 02:20:00Z],
        started_at: ~U[2026-09-17 02:20:03Z],
        ended_at: nil,
        terminal_reason: nil,
        archive_state: :unconfirmed
      }
    ]

    repository =
      start_supervised!({TestAdminRepository, {:ok, {tenant, call_specs, false, calls, 3}}})

    assert {:ok,
            %CallDirectoryPage{
              tenant: ^tenant,
              call_specs: ^call_specs,
              call_specs_truncated: false,
              selected_call_spec_id: "delivery-rescheduling",
              calls: ^calls,
              page: 2,
              page_size: 2,
              total: 3,
              total_pages: 2
            }} =
             Vxpipe.Calls.list_operator_calls(
               InstallationOperator.authority(),
               tenant.key,
               call_spec_id: "delivery-rescheduling",
               page: 2,
               limit: 2,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert_received {:admin_repository_list_calls, "AAAAAAAAAAAAAAAA", "delivery-rescheduling", 2,
                     2}
  end

  test "keeps missing call resources, unavailable storage, and operator authority distinct" do
    missing_tenant =
      start_supervised!({TestAdminRepository, {:error, :tenant_not_found}}, id: :call_tenant)

    missing_call_spec =
      start_supervised!({TestAdminRepository, {:error, :call_spec_not_found}},
        id: :call_spec
      )

    failed =
      start_supervised!({TestAdminRepository, {:error, :database_unavailable}}, id: :call_failed)

    for {repository, expected} <- [
          {missing_tenant, :tenant_not_found},
          {missing_call_spec, :call_spec_not_found},
          {failed, :database_unavailable}
        ] do
      assert {:error, ^expected} =
               Vxpipe.Calls.list_operator_calls(
                 InstallationOperator.authority(),
                 "AAAAAAAAAAAAAAAA",
                 call_spec_id: "delivery-rescheduling",
                 admin_repository: TestAdminRepository.admin_repository(repository)
               )
    end

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.list_operator_calls(
               %Principal{
                 tenant_key: "AAAAAAAAAAAAAAAA",
                 api_key_id: "key",
                 scopes: MapSet.new([:calls])
               },
               "AAAAAAAAAAAAAAAA",
               admin_repository: TestAdminRepository.admin_repository(failed)
             )
  end

  test "lists metadata-only tenant services for installation operator authority" do
    tenant = %Tenant{
      key: "AAAAAAAAAAAAAAAA",
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    credentials = [
      %ProviderCredential{
        id: "11111111-1111-4111-8111-111111111111",
        tenant_key: tenant.key,
        provider: "google",
        name: "primary",
        auth_kind: "api_key",
        inserted_at: ~U[2026-09-17 02:00:00Z],
        updated_at: ~U[2026-09-17 02:00:00Z]
      },
      %ProviderCredential{
        id: "33333333-3333-4333-8333-333333333333",
        tenant_key: tenant.key,
        provider: "telnyx",
        name: "voice",
        auth_kind: "api_key",
        inserted_at: ~U[2026-09-17 02:01:00Z],
        updated_at: ~U[2026-09-17 02:01:00Z]
      },
      %ProviderCredential{
        id: "44444444-4444-4444-8444-444444444444",
        tenant_key: tenant.key,
        provider: "rime",
        name: "rime",
        auth_kind: "api_key",
        inserted_at: ~U[2026-09-17 02:01:00Z],
        updated_at: ~U[2026-09-17 02:01:00Z]
      }
    ]

    telephony_services = [
      %TelephonyService{
        id: "22222222-2222-4222-8222-222222222222",
        tenant_key: tenant.key,
        name: "voice",
        ingress_key: "voice-ingress",
        provider: "telnyx",
        provider_connection_id: "connection-primary",
        credential_id: "33333333-3333-4333-8333-333333333333",
        public_key: nil,
        outbound_number: "+14155550100",
        answering_machine_detection: :disabled,
        media_token_ttl_ms: 60_000,
        webhook_tolerance_seconds: 300
      }
    ]

    repository =
      start_supervised!(
        {TestAdminRepository, {:ok, {tenant, credentials, telephony_services, false}}}
      )

    assert {:ok,
            %ServiceDirectory{
              tenant: ^tenant,
              credentials: ^credentials,
              telephony_services: ^telephony_services,
              truncated: false
            }} =
             Vxpipe.Calls.list_operator_services(
               InstallationOperator.authority(),
               tenant.key,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert_received {:admin_repository_list_services, "AAAAAAAAAAAAAAAA"}

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.list_operator_services(
               %Principal{
                 tenant_key: tenant.key,
                 api_key_id: "key",
                 scopes: MapSet.new([:admin])
               },
               tenant.key,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )
  end

  test "creates each currently supported credential contract with a provider-owned name" do
    tenant_key = "AAAAAAAAAAAAAAAA"

    cases = [
      {"google", "api_key", %{"api_key" => "google-secret"}},
      {"deepgram", "api_key", %{"api_key" => "deepgram-secret"}},
      {"zenmux", "api_key", %{"api_key" => "zenmux-secret"}},
      {"telnyx", "api_key", %{"api_key" => "telnyx-secret"}},
      {"twilio", "account_sid_auth_token",
       %{
         "account_sid" => "AC11111111111111111111111111111111",
         "auth_token" => "twilio-secret"
       }}
    ]

    for {{provider, auth_kind, payload}, index} <- Enum.with_index(cases, 1) do
      suffix = String.pad_leading(Integer.to_string(index), 12, "0")

      returned = %ProviderCredential{
        id: "11111111-1111-4111-8111-#{suffix}",
        tenant_key: tenant_key,
        provider: provider,
        name: provider,
        auth_kind: auth_kind
      }

      repository = TestOperatorCredentialRepository.repository(self(), {:ok, returned})

      assert {:ok, ^returned} =
               Vxpipe.Calls.create_operator_credential(
                 InstallationOperator.authority(),
                 tenant_key,
                 provider,
                 provider,
                 auth_kind,
                 payload,
                 provider_credential_repository: repository,
                 uuid_generator: fn -> returned.id end
               )

      assert_received {:operator_credential_provisioned, provisioned, ^payload}
      assert provisioned.id == returned.id
      assert provisioned.tenant_key == tenant_key
      assert provisioned.provider == provider
      assert provisioned.name == provider
      assert provisioned.auth_kind == auth_kind
    end
  end

  test "tests an operator credential without persisting it" do
    validator = TestOperatorCredentialValidator.validator(self(), :ok)

    assert :ok =
             Vxpipe.Calls.validate_operator_credential(
               InstallationOperator.authority(),
               "AAAAAAAAAAAAAAAA",
               "deepgram",
               "deepgram",
               "api_key",
               %{"api_key" => "private"},
               provider_credential_validator: validator
             )

    assert_received {:operator_credential_validated, "deepgram", "api_key",
                     %{"api_key" => "private"}}

    refute_received {:operator_credential_provisioned, _, _}
  end

  test "returns provider rejection without persisting the tested credential" do
    validator =
      TestOperatorCredentialValidator.validator(self(), {:error, :provider_credential_rejected})

    assert {:error, :provider_credential_rejected} =
             Vxpipe.Calls.validate_operator_credential(
               InstallationOperator.authority(),
               "AAAAAAAAAAAAAAAA",
               "deepgram",
               "deepgram",
               "api_key",
               %{"api_key" => "rejected"},
               provider_credential_validator: validator
             )

    assert_received {:operator_credential_validated, "deepgram", "api_key",
                     %{"api_key" => "rejected"}}

    refute_received {:operator_credential_provisioned, _, _}
  end

  test "only installation operators can test a platform-owned credential" do
    options = [
      provider_credential_validator: TestOperatorCredentialValidator.validator(self(), :ok)
    ]

    tenant_principal = %Principal{
      tenant_key: "AAAAAAAAAAAAAAAA",
      api_key_id: "tenant-key",
      scopes: MapSet.new([:admin])
    }

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.validate_operator_credential(
               tenant_principal,
               :platform,
               "google",
               "shared-model",
               "api_key",
               %{"api_key" => "example-key"},
               options
             )

    refute_received {:operator_credential_validated, _, _, _}

    assert :ok =
             Vxpipe.Calls.validate_operator_credential(
               InstallationOperator.authority(),
               :platform,
               "google",
               "shared-model",
               "api_key",
               %{"api_key" => "example-key"},
               options
             )

    assert_received {:operator_credential_validated, "google", "api_key",
                     %{"api_key" => "example-key"}}

    refute_received {:operator_credential_provisioned, _, _}
  end

  test "ordinary provisioning cannot claim upstream validation evidence" do
    tenant_key = "AAAAAAAAAAAAAAAA"

    returned = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: tenant_key,
      provider: "google",
      name: "google",
      auth_kind: "api_key"
    }

    repository = TestOperatorCredentialRepository.repository(self(), {:ok, returned})

    assert {:ok, ^returned} =
             Vxpipe.Calls.create_operator_credential(
               InstallationOperator.authority(),
               tenant_key,
               "google",
               "google",
               "api_key",
               %{"api_key" => "private"},
               provider_credential_repository: repository,
               last_validated_at: ~U[2026-09-18 05:00:00Z],
               uuid_generator: fn -> returned.id end
             )

    assert_received {:operator_credential_provisioned,
                     %ProviderCredential{last_validated_at: nil}, _payload}
  end

  test "replaces an operator credential without changing its identity" do
    tenant_key = "AAAAAAAAAAAAAAAA"

    returned = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: tenant_key,
      provider: "google",
      name: "google",
      auth_kind: "api_key",
      version: 2,
      secret_hints: %{"api_key" => "8c4a"}
    }

    repository = TestOperatorCredentialRepository.repository(self(), {:ok, returned})

    assert {:ok, ^returned} =
             Vxpipe.Calls.update_operator_credential(
               InstallationOperator.authority(),
               tenant_key,
               returned.id,
               "google",
               "api_key",
               %{"api_key" => "replacement-8c4a"},
               provider_credential_repository: repository
             )

    assert_received {:operator_credential_replaced, ^tenant_key, credential_id, "google",
                     "api_key", %{"api_key" => "replacement-8c4a"}}

    assert credential_id == returned.id
  end

  test "credential creation preserves validation, duplicate, storage, and authority failures" do
    tenant_key = "AAAAAAAAAAAAAAAA"

    repository =
      TestOperatorCredentialRepository.repository(
        self(),
        {:error, :provider_credential_conflict}
      )

    options = [provider_credential_repository: repository]

    assert {:error, :provider_credential_conflict} =
             Vxpipe.Calls.create_operator_credential(
               InstallationOperator.authority(),
               tenant_key,
               "google",
               "primary",
               "api_key",
               %{"api_key" => "private"},
               options
             )

    assert {:error, :invalid_provider_auth} =
             Vxpipe.Calls.create_operator_credential(
               InstallationOperator.authority(),
               tenant_key,
               "unsupported",
               "primary",
               "api_key",
               %{"api_key" => "private"},
               options
             )

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.create_operator_credential(
               %Principal{
                 tenant_key: tenant_key,
                 api_key_id: "key",
                 scopes: MapSet.new([:admin])
               },
               tenant_key,
               "google",
               "primary",
               "api_key",
               %{"api_key" => "private"},
               options
             )
  end

  test "platform credential replacement validates the tagged owner without treating it as a tenant key" do
    returned = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      owner: :platform,
      tenant_key: nil,
      provider: "google",
      name: "shared-model",
      auth_kind: "api_key",
      version: 2
    }

    options = [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, returned})
    ]

    assert {:ok, ^returned} =
             Vxpipe.Calls.update_operator_credential(
               InstallationOperator.authority(),
               :platform,
               returned.id,
               "google",
               "api_key",
               %{"api_key" => "replacement"},
               options
             )

    foreign = %{returned | owner: {:tenant, "BBBBBBBBBBBBBBBB"}, tenant_key: "BBBBBBBBBBBBBBBB"}

    options = [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, foreign})
    ]

    assert {:error, :provider_credential_write_failed} =
             Vxpipe.Calls.update_operator_credential(
               InstallationOperator.authority(),
               :platform,
               returned.id,
               "google",
               "api_key",
               %{"api_key" => "replacement"},
               options
             )
  end

  test "rejects repository metadata that crosses the requested tenant boundary" do
    tenant = %Tenant{
      key: "AAAAAAAAAAAAAAAA",
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    foreign = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: "BBBBBBBBBBBBBBBB",
      provider: "google",
      name: "primary",
      auth_kind: "api_key"
    }

    directory_repository =
      start_supervised!({TestAdminRepository, {:ok, {tenant, [foreign], [], false}}})

    assert {:error, :service_directory_unavailable} =
             Vxpipe.Calls.list_operator_services(
               InstallationOperator.authority(),
               tenant.key,
               admin_repository: TestAdminRepository.admin_repository(directory_repository)
             )

    credential_repository =
      TestOperatorCredentialRepository.repository(self(), {:ok, foreign})

    assert {:error, :provider_credential_write_failed} =
             Vxpipe.Calls.create_operator_credential(
               InstallationOperator.authority(),
               tenant.key,
               "google",
               "primary",
               "api_key",
               %{"api_key" => "private"},
               provider_credential_repository: credential_repository
             )
  end
end
