defmodule Vxpipe.Persistence.SharedTelnyxReviewTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    OperatorTelnyxConnection,
    OperatorTelephonyApplications,
    TelephonyServices
  }

  alias Vxpipe.Persistence.{
    AdminStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    TelephonyServiceStore
  }

  setup do
    {:ok, keyring} = CredentialKeyring.new("review", %{"review" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      admin_repository: {AdminStore, Repo}
    ]

    operator = InstallationOperator.authority()
    {:ok, tenant, _} = Administration.bootstrap_tenant("Shared Telnyx review", [:admin], options)

    {:ok, _} =
      OperatorTelnyxConnection.update(
        operator,
        :platform,
        %{
          "application_id" => "shared-app",
          "credentials" => %{
            "api_key" => "synthetic-review-key",
            "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
          }
        },
        options
      )

    {:ok, saved} =
      OperatorTelnyxConnection.update(operator, tenant.key, %{"application_id" => nil}, options)

    [application] = saved.applications
    actions = MapSet.new(["tenant_services.read", "tenant_services.write"])

    principal = %Vxpipe.Identity.Principal{
      user_public_id: "service-writer",
      session_public_id: "review-session",
      account_kind: :member,
      assigned_tenants: %{},
      all_tenant_actions: actions,
      grants: actions
    }

    %{tenant: tenant.key, application: application, principal: principal, options: options}
  end

  test "service-only writer may override and reset the application without credential authority",
       data do
    assert {:ok, own} =
             OperatorTelnyxConnection.update(
               data.principal,
               data.tenant,
               %{"service_id" => data.application.id, "application_id" => "dedicated-app"},
               data.options
             )

    assert own.credential.source == :platform
    assert hd(own.applications).provider_connection_id == "dedicated-app"

    assert {:ok, inherited} =
             OperatorTelnyxConnection.update(
               data.principal,
               data.tenant,
               %{"service_id" => data.application.id, "application_id" => nil},
               data.options
             )

    assert inherited.credential.source == :platform
    assert hd(inherited.applications).provider_connection_id == nil
  end

  test "an inherited application's outbound number can change without changing its app", data do
    assert {:ok, updated} =
             OperatorTelephonyApplications.update(
               data.principal,
               data.tenant,
               data.application.id,
               %{"provider_connection_id" => nil, "outbound_number" => "+15550002000"},
               data.options
             )

    assert updated.provider_connection_id == nil
    assert updated.outbound_number == "+15550002000"

    assert {:ok, resolved} =
             TelephonyServices.resolve(data.tenant, data.application.name, data.options)

    assert resolved.service.application_owner == :platform
    assert resolved.service.provider_connection_id == "shared-app"
    assert resolved.service.outbound_number == "+15550002000"
  end
end
