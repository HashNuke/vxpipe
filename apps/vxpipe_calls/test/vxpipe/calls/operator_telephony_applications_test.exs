defmodule Vxpipe.Calls.OperatorTelephonyApplicationsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{InstallationOperator, OperatorTelephonyApplications, Principal, PublicId}

  test "operator authority and input allowlists are checked before reaching repositories" do
    tenant = "AAAAAAAAAAAAAAAA"
    id = PublicId.uuid()
    attributes = %{"name" => "support", "provider_connection_id" => "application-id"}
    options = [admin_repository: nil, telephony_service_repository: nil]
    principal = %Principal{tenant_key: tenant, api_key_id: "key", scopes: MapSet.new([:admin])}

    for authority <- [nil, %{grant: :installation_operator}, principal] do
      assert {:error, :installation_operator_required} =
               OperatorTelephonyApplications.create(authority, tenant, attributes, options)

      assert {:error, :installation_operator_required} =
               OperatorTelephonyApplications.update(authority, tenant, id, attributes, options)

      assert {:error, :installation_operator_required} =
               OperatorTelephonyApplications.list(authority, tenant, options)
    end

    operator = InstallationOperator.authority()

    for field <- [
          "provider",
          "credential_name",
          "credential_id",
          "public_key",
          "api_key",
          "ingress_key",
          "tenant_key",
          "owner"
        ] do
      assert {:error, :invalid_telephony_service} =
               OperatorTelephonyApplications.create(
                 operator,
                 tenant,
                 Map.put(attributes, field, "not-allowed"),
                 options
               )

      assert {:error, :invalid_telephony_service} =
               OperatorTelephonyApplications.update(
                 operator,
                 tenant,
                 id,
                 %{field => "not-allowed"},
                 options
               )
    end

    assert {:error, :invalid_telephony_service} =
             OperatorTelephonyApplications.update(
               operator,
               tenant,
               id,
               %{"name" => "renamed"},
               options
             )
  end
end
