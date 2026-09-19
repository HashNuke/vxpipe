defmodule Vxpipe.Calls.OperatorServiceBindingsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{InstallationOperator, Principal, TestOperatorCredentialRepository}

  test "only an installation operator can change a tenant's exact binding policy" do
    tenant = "AAAAAAAAAAAAAAAA"

    options = [
      provider_credential_repository: TestOperatorCredentialRepository.repository(self(), :ok)
    ]

    principal = %Principal{tenant_key: tenant, api_key_id: "key", scopes: MapSet.new([:admin])}

    assert {:error, :installation_operator_required} =
             Vxpipe.Calls.set_operator_service_policy(
               principal,
               tenant,
               "google",
               "named-model",
               :disabled,
               options
             )

    refute_received {:operator_policy_changed, _, _, _, _}

    for policy <- [:override, :disabled, :inherit] do
      assert :ok =
               Vxpipe.Calls.set_operator_service_policy(
                 InstallationOperator.authority(),
                 tenant,
                 "google",
                 "named-model",
                 policy,
                 options
               )

      assert_received {:operator_policy_changed, ^tenant, "google", "named-model", ^policy}
    end

    assert {:error, :invalid_service_policy} =
             Vxpipe.Calls.set_operator_service_policy(
               InstallationOperator.authority(),
               tenant,
               "google",
               "named-model",
               :fallback,
               options
             )

    refute_received {:operator_policy_changed, _, _, _, _}
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

    assert {:ok, ^result} =
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
