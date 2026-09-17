defmodule Vxpipe.Calls.OperatorAdministrationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    DefinitionPage,
    DefinitionSummary,
    InstallationOperator,
    Principal,
    Tenant,
    TenantPage
  }

  alias Vxpipe.Calls.TestAdminRepository

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

  test "lists one tenant's bounded definition summaries" do
    tenant = %Tenant{
      key: "AAAAAAAAAAAAAAAA",
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    definitions = [
      %DefinitionSummary{
        id: "delivery-rescheduling",
        name: "Delivery rescheduling",
        latest_revision: 4,
        published_revision: 3,
        call_count: 5,
        updated_at: ~U[2026-09-17 03:00:00Z]
      }
    ]

    repository = start_supervised!({TestAdminRepository, {:ok, {tenant, definitions, 3}}})

    assert {:ok,
            %DefinitionPage{
              tenant: ^tenant,
              definitions: ^definitions,
              page: 2,
              page_size: 2,
              total: 3,
              total_pages: 2
            }} =
             Vxpipe.Calls.list_operator_definitions(
               InstallationOperator.authority(),
               tenant.key,
               page: 2,
               limit: 2,
               admin_repository: TestAdminRepository.admin_repository(repository)
             )

    assert_received {:admin_repository_list_definitions, "AAAAAAAAAAAAAAAA", 2, 2}
  end

  test "keeps missing definition tenants and unavailable storage distinct" do
    missing = start_supervised!({TestAdminRepository, {:error, :tenant_not_found}}, id: :missing)

    failed =
      start_supervised!({TestAdminRepository, {:error, :database_unavailable}}, id: :failed)

    assert {:error, :tenant_not_found} =
             Vxpipe.Calls.list_operator_definitions(
               InstallationOperator.authority(),
               "missing",
               admin_repository: TestAdminRepository.admin_repository(missing)
             )

    assert {:error, :database_unavailable} =
             Vxpipe.Calls.list_operator_definitions(
               InstallationOperator.authority(),
               "AAAAAAAAAAAAAAAA",
               admin_repository: TestAdminRepository.admin_repository(failed)
             )

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.list_operator_definitions(
               %Principal{
                 tenant_key: "AAAAAAAAAAAAAAAA",
                 api_key_id: "key",
                 scopes: MapSet.new()
               },
               "AAAAAAAAAAAAAAAA",
               admin_repository: TestAdminRepository.admin_repository(failed)
             )
  end
end
