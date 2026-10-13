defmodule Vxpipe.Calls.OperatorServiceBindingsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{InstallationOperator, Principal, TestOperatorCredentialRepository}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  test "service-only reader cannot see credential identifiers in bindings" do
    tenant = "AAAAAAAAAAAAAAAA"
    binding = %{
      provider: "deepgram", name: "deepgram", source: :tenant, status: :connected,
      credential_id: "credential-id", platform_available: false,
      saved_fields: ["api_key"], last_validated_at: nil
    }
    options = [provider_credential_repository:
      TestOperatorCredentialRepository.repository(self(), {:ok, %{tenant: %{key: tenant, name: "Example"}, bindings: [binding]}})]
    principal = %UserPrincipal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: :member,
      grants: MapSet.new(["tenant_services.read"]),
      assigned_tenants: %{tenant => :read},
      all_tenant_actions: MapSet.new()
    }

    assert {:ok, %{bindings: [visible]}} =
             Vxpipe.Calls.list_operator_service_bindings(principal, tenant, options)
    assert visible.credential_id == nil
    assert visible.saved_fields == []
  end

  test "operator inventory includes public models before a tenant exists" do
    options = [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, %{tenant: nil, bindings: []}})
    ]

    assert {:ok, %{model_catalog: catalog}} =
             Vxpipe.Calls.list_operator_service_bindings(
               InstallationOperator.authority(),
               :platform,
               options
             )

    assert [%{id: "flux"}] = catalog["text_to_speech"]["deepgram"]
  end

  test "only an installation operator can delete credentials within their exact owner" do
    tenant = "AAAAAAAAAAAAAAAA"

    options = [
      provider_credential_repository: TestOperatorCredentialRepository.repository(self(), :ok)
    ]

    principal = %Principal{tenant_key: tenant, api_key_id: "key", scopes: MapSet.new([:admin])}

    for scope <- [tenant, :platform] do
      assert {:error, :installation_operator_required} =
               Vxpipe.Calls.delete_operator_credential(principal, scope, "credential-id", options)

      refute_received {:operator_credential_deleted, _, _}

      assert :ok =
               Vxpipe.Calls.delete_operator_credential(
                 InstallationOperator.authority(),
                 scope,
                 "credential-id",
                 options
               )

      assert_received {:operator_credential_deleted, ^scope, "credential-id"}
    end
  end

  test "accepts a tagged tenant owner and strips extra repository metadata" do
    tenant_key = "AAAAAAAAAAAAAAAA"
    directory = %{tenant: %{key: tenant_key, name: "Example", private: "hidden"}, bindings: []}

    options = [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, directory})
    ]

    for owner <- [tenant_key, {:tenant, tenant_key}] do
      assert {:ok, %{tenant: %{key: ^tenant_key, name: "Example"} = tenant, bindings: []}} =
               Vxpipe.Calls.list_operator_service_bindings(
                 InstallationOperator.authority(),
                 owner,
                 options
               )

      refute Map.has_key?(tenant, :private)
      assert_received {:operator_bindings_requested, ^owner}
    end
  end

  test "only installation authority can read platform or tenant effective bindings" do
    result = %{tenant: nil, bindings: []}

    options = [
      provider_credential_repository:
        TestOperatorCredentialRepository.repository(self(), {:ok, result})
    ]

    principal = %Principal{
      tenant_key: "AAAAAAAAAAAAAAAA",
      api_key_id: "key",
      scopes: MapSet.new([:admin])
    }

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.list_operator_service_bindings(principal, :platform, options)

    refute_received {:operator_bindings_requested, _}

    assert {:ok, %{tenant: nil, bindings: [], model_catalog: _catalog}} =
             Vxpipe.Calls.list_operator_service_bindings(
               InstallationOperator.authority(),
               :platform,
               options
             )

    assert_received {:operator_bindings_requested, :platform}

    assert {:error, :service_directory_unavailable} =
             Vxpipe.Calls.list_operator_service_bindings(
               InstallationOperator.authority(),
               "AAAAAAAAAAAAAAAA",
               options
             )
  end
end
