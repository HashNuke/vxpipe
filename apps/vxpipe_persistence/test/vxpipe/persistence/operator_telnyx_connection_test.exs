defmodule Vxpipe.Persistence.OperatorTelnyxConnectionTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    OperatorTelnyxConnection,
    OperatorTelephonyApplications,
    ProviderCredentials,
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
    {:ok, keyring} = CredentialKeyring.new("telnyx", %{"telnyx" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      admin_repository: {AdminStore, Repo}
    ]

    {:ok, tenant, _} = Administration.bootstrap_tenant("Telnyx tenant", [:admin], options)
    %{options: options, tenant: tenant.key, operator: InstallationOperator.authority()}
  end

  test "one save persists both sections and enforces tenant reset requirements", data do
    assert {:ok, platform} =
             OperatorTelnyxConnection.update(
               data.operator,
               :platform,
               %{"application_id" => "shared", "credentials" => credentials("platform")},
               data.options
             )

    assert platform.platform_application_id == "shared"
    assert platform.credential.source == :platform
    refute inspect(platform) =~ "platform-private"

    assert {:ok, tenant} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "own", "credentials" => credentials("tenant")},
               data.options
             )

    [application] = tenant.applications
    assert application.provider_connection_id == "own"
    assert tenant.credential.source == :tenant

    assert {:error, :telnyx_application_required} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"service_id" => application.id, "application_id" => nil},
               data.options
             )

    assert {:ok, snapshot} =
             TelephonyServices.resolve(data.tenant, application.name, data.options)

    assert snapshot.service.provider_connection_id == "own"
    assert snapshot.credential.payload["api_key"] == "tenant-private"

    assert {:ok, own_app} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"service_id" => application.id, "application_id" => "own", "credentials" => nil},
               data.options
             )

    assert own_app.credential.source == :platform

    assert {:ok, reopened} =
             OperatorTelnyxConnection.get(data.operator, data.tenant, data.options)

    assert reopened == own_app

    assert {:ok, snapshot} =
             TelephonyServices.resolve(data.tenant, application.name, data.options)

    assert snapshot.service.provider_connection_id == "own"
    assert snapshot.credential.payload["api_key"] == "platform-private"
  end

  test "a failed application write rolls back the credential replacement", data do
    {:ok, _} =
      ProviderCredentials.provision(
        data.tenant,
        "telnyx",
        "telnyx",
        "api_key",
        credentials("original"),
        data.options
      )

    assert {:ok, before} =
             ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert {:error, :telephony_service_not_found} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{
                 "credentials" => credentials("replacement"),
                 "service_id" => Vxpipe.Calls.PublicId.uuid(),
                 "application_id" => "own"
               },
               data.options
             )

    assert {:ok, after_failure} =
             ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert after_failure == before
  end

  test "each changed section requires its own existing permission", data do
    principal = %Vxpipe.Identity.Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["tenant_services.read", "tenant_services.write"]),
      assigned_tenants: %{data.tenant => :read_write},
      all_tenant_actions: MapSet.new()
    }

    assert {:error, :forbidden} =
             OperatorTelnyxConnection.update(
               principal,
               data.tenant,
               %{"application_id" => "own", "credentials" => credentials("unauthorized")},
               data.options
             )

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert {:error, :forbidden} =
             OperatorTelnyxConnection.update(
               principal,
               :platform,
               %{"application_id" => "forbidden"},
               data.options
             )
  end

  test "omitted masked fields keep only the current owner's saved values", data do
    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        :platform,
        %{"application_id" => "shared", "credentials" => credentials("platform")},
        data.options
      )

    assert {:error, :invalid_provider_auth} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "own", "credentials" => %{"api_key" => "incomplete"}},
               data.options
             )

    assert {:ok, []} = ProviderCredentials.list(data.tenant, data.options)

    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        data.tenant,
        %{"credentials" => credentials("tenant"), "application_id" => "own"},
        data.options
      )

    {:ok, before} = ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert {:ok, _} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "own", "credentials" => %{"api_key" => "updated-private"}},
               data.options
             )

    assert {:ok, replaced} =
             ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert replaced.payload == %{before.payload | "api_key" => "updated-private"}

    new_public = Base.encode64(:binary.copy(<<2>>, 32))

    assert {:ok, safe} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "own", "credentials" => %{"public_key" => new_public}},
               data.options
             )

    assert {:ok, replaced} =
             ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert replaced.payload == %{"api_key" => "updated-private", "public_key" => new_public}
    refute inspect(safe) =~ "updated-private"
    refute inspect(safe) =~ new_public
  end

  test "a malformed or ambiguous service selection never edits another named binding", data do
    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        :platform,
        %{"credentials" => credentials("platform")},
        data.options
      )

    {:ok, support} =
      OperatorTelephonyApplications.create(
        data.operator,
        data.tenant,
        %{
          "name" => "support",
          "provider_connection_id" => "support-app",
          "outbound_number" => "+15550001001"
        },
        data.options
      )

    assert {:error, :invalid_telephony_service} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"service_id" => nil, "application_id" => "wrong"},
               data.options
             )

    {:ok, _sales} =
      OperatorTelephonyApplications.create(
        data.operator,
        data.tenant,
        %{"name" => "sales", "provider_connection_id" => "sales-app"},
        data.options
      )

    assert {:error, :telephony_service_required} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "wrong"},
               data.options
             )

    assert {:ok, _} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"service_id" => support.id, "application_id" => "new-support"},
               data.options
             )

    assert {:ok, current} = TelephonyServices.fetch(data.tenant, "support", data.options)
    assert current.id == support.id
    assert current.outbound_number == support.outbound_number
    assert current.provider_connection_id == "new-support"
    assert {:ok, sales} = TelephonyServices.fetch(data.tenant, "sales", data.options)
    assert sales.provider_connection_id == "sales-app"
  end

  test "section permissions allow independent changes and invalid credentials roll back", data do
    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        :platform,
        %{"application_id" => "shared", "credentials" => credentials("platform")},
        data.options
      )

    {:ok, initial} =
      OperatorTelnyxConnection.update(
        data.operator,
        data.tenant,
        %{"application_id" => "own"},
        data.options
      )

    [service] = initial.applications

    principal = %Vxpipe.Identity.Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      assigned_tenants: %{data.tenant => :read_write},
      all_tenant_actions: MapSet.new(),
      grants: MapSet.new(["tenant_services.read", "tenant_services.write"])
    }

    assert {:ok, _} =
             OperatorTelnyxConnection.update(
               principal,
               data.tenant,
               %{"service_id" => service.id, "application_id" => nil},
               data.options
             )

    key_editor = %{
      principal
      | grants: MapSet.new(["tenant_services.read", "tenant_api_keys.write"])
    }

    assert {:error, :forbidden} =
             OperatorTelnyxConnection.update(
               key_editor,
               data.tenant,
               %{"application_id" => "own", "credentials" => credentials("own")},
               data.options
             )

    assert {:ok, _} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "own", "credentials" => credentials("own")},
               data.options
             )

    assert {:ok, saved} =
             OperatorTelnyxConnection.update(
               key_editor,
               data.tenant,
               %{"credentials" => nil},
               data.options
             )

    assert hd(saved.applications).source == :tenant

    assert {:error, :forbidden} =
             OperatorTelnyxConnection.update(
               key_editor,
               data.tenant,
               %{"application_id" => "denied"},
               data.options
             )

    assert {:error, :invalid_provider_auth} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"application_id" => "invalid", "credentials" => %{"api_key" => ""}},
               data.options
             )

    assert {:ok, ^saved} = OperatorTelnyxConnection.get(data.operator, data.tenant, data.options)
  end

  test "tenant credential edits require an explicitly supplied dedicated application", data do
    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        :platform,
        %{"application_id" => "shared", "credentials" => credentials("platform")},
        data.options
      )

    for attrs <- [
          %{"credentials" => credentials("own")},
          %{"credentials" => credentials("own"), "application_id" => nil}
        ] do
      assert {:error, :telnyx_application_required} =
               OperatorTelnyxConnection.update(data.operator, data.tenant, attrs, data.options)

      assert {:ok, []} = ProviderCredentials.list(data.tenant, data.options)
    end

    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        data.tenant,
        %{"credentials" => credentials("own"), "application_id" => "dedicated"},
        data.options
      )

    assert {:error, :telnyx_application_required} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{"credentials" => credentials("replacement")},
               data.options
             )

    assert {:ok, snapshot} =
             ProviderCredentials.resolve(data.tenant, "telnyx", "telnyx", data.options)

    assert snapshot.payload["api_key"] == "own-private"
  end

  test "credential changes cannot leave another named binding on the shared application", data do
    {:ok, _} =
      OperatorTelnyxConnection.update(
        data.operator,
        :platform,
        %{"application_id" => "shared", "credentials" => credentials("platform")},
        data.options
      )

    applications =
      for name <- ["support", "sales"] do
        {:ok, application} =
          OperatorTelephonyApplications.create(
            data.operator,
            data.tenant,
            %{"name" => name, "provider_connection_id" => nil},
            data.options
          )

        application
      end

    first = hd(applications)

    assert {:error, :telnyx_application_required} =
             OperatorTelnyxConnection.update(
               data.operator,
               data.tenant,
               %{
                 "service_id" => first.id,
                 "application_id" => "own-support",
                 "credentials" => credentials("tenant")
               },
               data.options
             )

    assert {:ok, saved} = OperatorTelnyxConnection.get(data.operator, data.tenant, data.options)
    assert saved.credential.source == :platform
    assert Enum.all?(saved.applications, &is_nil(&1.provider_connection_id))
  end

  defp credentials(marker),
    do: %{
      "api_key" => marker <> "-private",
      "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
    }
end
