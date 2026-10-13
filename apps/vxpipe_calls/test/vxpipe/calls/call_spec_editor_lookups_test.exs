defmodule Vxpipe.Calls.CallSpecEditorLookupsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    InstallationOperator,
    ProviderCredential,
    Tenant,
    TelephonyService
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  defmodule TestEditorBindingsRepository do
    def list_bindings(result, scope) do
      send(self(), {:editor_bindings_requested, scope})
      result
    end
  end

  defmodule TestEditorAdminRepository do
    def list_services(%{services: result}, tenant_key) do
      send(self(), {:editor_list_services, tenant_key})
      result
    end

    def list_telephony_applications(%{applications: result}, tenant_key) do
      send(self(), {:editor_list_applications, tenant_key})
      result
    end
  end

  defp member_principal(
         tenant,
         grants \\ ["calls.read", "calls.write", "call_specs.read", "call_specs.write"]
       ) do
    %UserPrincipal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: :member,
      grants: MapSet.new(grants),
      assigned_tenants: %{tenant => :read_write},
      all_tenant_actions: MapSet.new()
    }
  end

  defp privileged_principal(tenant) do
    %UserPrincipal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: :admin,
      grants:
        MapSet.new([
          "calls.read",
          "calls.write",
          "call_specs.read",
          "call_specs.write",
          "call_specs.use_platform_services"
        ]),
      assigned_tenants: %{tenant => :read_write},
      all_tenant_actions: MapSet.new()
    }
  end

  defp tenant_fixture(key) do
    %Tenant{key: key, name: "Tenant #{key}", inserted_at: ~U[2026-09-17 01:00:00Z]}
  end

  defp options(bindings_result, services_result, applications_result) do
    admin_context = %{services: services_result, applications: applications_result}

    [
      provider_credential_repository: {TestEditorBindingsRepository, bindings_result},
      admin_repository: {TestEditorAdminRepository, admin_context}
    ]
  end

  defp bindings_fixture(tenant_key) do
    {:ok,
     %{
       tenant: %{key: tenant_key, name: "Tenant #{tenant_key}"},
       bindings: [
         %{
           provider: "deepgram",
           name: "deepgram",
           source: :tenant,
           status: :connected,
           credential_id: nil,
           platform_available: false,
           saved_fields: ["api_key"],
           last_validated_at: nil
         },
         %{
           provider: "google",
           name: "shared",
           source: :platform,
           status: :connected,
           credential_id: nil,
           platform_available: true,
           saved_fields: ["api_key"],
           last_validated_at: nil
         }
       ]
     }}
  end

  defp services_fixture(tenant_key) do
    tenant = tenant_fixture(tenant_key)

    credential = %ProviderCredential{
      id: "11111111-1111-4111-8111-111111111111",
      tenant_key: tenant_key,
      provider: "telnyx",
      name: "voice",
      auth_kind: "api_key"
    }

    service = %TelephonyService{
      id: "22222222-2222-4222-8222-222222222222",
      tenant_key: tenant_key,
      name: "voice",
      ingress_key: "voice-ingress-secret",
      provider: "telnyx",
      provider_connection_id: "connection-primary",
      credential_id: credential.id,
      credential_name: nil,
      credential_owner: nil,
      public_key: nil,
      outbound_number: "+14155550100",
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    {:ok, {tenant, [credential], [service], false}}
  end

  defp applications_fixture(tenant_key) do
    tenant = tenant_fixture(tenant_key)

    service = %TelephonyService{
      id: "33333333-3333-4333-8333-333333333333",
      tenant_key: tenant_key,
      name: "support-app",
      ingress_key: "app-ingress-secret",
      provider: "telnyx",
      provider_connection_id: "app-connection-1",
      credential_id: nil,
      credential_name: "telnyx",
      credential_owner: nil,
      public_key: nil,
      outbound_number: nil,
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    {:ok, {tenant, [service], [], false}}
  end

  defp platform_service_fixture(tenant_key) do
    %TelephonyService{
      id: "44444444-4444-4444-8444-444444444444",
      tenant_key: tenant_key,
      name: "platform-voice",
      ingress_key: "platform-ingress-1",
      provider: "telnyx",
      provider_connection_id: "connection-platform",
      credential_id: "55555555-5555-4555-8555-555555555555",
      credential_name: "telnyx",
      credential_owner: :platform,
      public_key: "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=",
      outbound_number: "+14155550200",
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }
  end

  test "assigned member with call_specs.read loads tenant-owned editor lookups without tenant_services.read" do
    opts =
      options(bindings_fixture(@tenant), services_fixture(@tenant), applications_fixture(@tenant))

    member = member_principal(@tenant)

    assert {:ok, lookups} = Vxpipe.Calls.list_call_spec_editor_lookups(member, @tenant, opts)

    assert lookups.tenant == %{key: @tenant, name: "Tenant #{@tenant}"}
    assert lookups.credential_names == %{"deepgram" => ["deepgram"]}

    assert [%{key: "support-app", name: "support-app", provider: "telnyx"}, %{key: "voice"}] =
             Enum.sort_by(lookups.telephony_services, & &1.key)

    assert Enum.all?(lookups.telephony_services, fn entry ->
             Map.keys(entry) |> Enum.sort() == [:key, :name, :provider]
           end)

    assert lookups.mcp_integrations == []
    assert lookups.truncated == false

    dumped = inspect(lookups) <> :erlang.term_to_binary(lookups)
    refute dumped =~ "voice-ingress-secret"
    refute dumped =~ "app-ingress-secret"
    refute dumped =~ "11111111-1111-4111-8111-111111111111"
  end

  test "editor lookups still enforce call_specs.read, tenant pinning and key format" do
    opts =
      options(bindings_fixture(@tenant), services_fixture(@tenant), applications_fixture(@tenant))

    no_grant =
      member_principal(@tenant, ["calls.read"])

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_call_spec_editor_lookups(no_grant, @tenant, opts)

    foreign = member_principal(@other)

    assert {:error, :forbidden} =
             Vxpipe.Calls.list_call_spec_editor_lookups(foreign, @tenant, opts)

    member = member_principal(@tenant)

    assert {:error, :invalid_tenant_key} =
             Vxpipe.Calls.list_call_spec_editor_lookups(member, "bad", opts)

    crossed_opts =
      options(bindings_fixture(@tenant), services_fixture(@other), applications_fixture(@tenant))

    assert {:error, _reason} =
             Vxpipe.Calls.list_call_spec_editor_lookups(member, @tenant, crossed_opts)
  end

  test "installation operator editor lookups keep full metadata path" do
    opts =
      options(bindings_fixture(@tenant), services_fixture(@tenant), applications_fixture(@tenant))

    assert {:ok, lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(
               InstallationOperator.authority(),
               @tenant,
               opts
             )

    assert Map.has_key?(lookups, :telephony_services)
    assert Map.has_key?(lookups, :credential_names)
  end

  test "member lookups hide platform-owned services while keeping tenant-owned" do
    {:ok, {tenant, [credential], [service], false}} = services_fixture(@tenant)

    platform_service = %TelephonyService{
      id: "44444444-4444-4444-8444-444444444444",
      tenant_key: @tenant,
      name: "platform-voice",
      ingress_key: "platform-ingress-secret",
      provider: "telnyx",
      provider_connection_id: "connection-platform",
      credential_id: "55555555-5555-4555-8555-555555555555",
      credential_name: nil,
      credential_owner: :platform,
      public_key: nil,
      outbound_number: "+14155550200",
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    mixed_services = {:ok, {tenant, [credential], [service, platform_service], false}}

    opts = options(bindings_fixture(@tenant), mixed_services, applications_fixture(@tenant))

    assert {:ok, lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(member_principal(@tenant), @tenant, opts)

    keys = Enum.map(lookups.telephony_services, & &1.key)
    assert "voice" in keys
    assert "support-app" in keys
    refute "platform-voice" in keys

    dumped = inspect(lookups) <> :erlang.term_to_binary(lookups)
    refute dumped =~ "platform-ingress-secret"
    refute dumped =~ "55555555-5555-4555-8555-555555555555"
  end

  test "privileged principal with call_specs.use_platform_services sees platform bindings and services" do
    {:ok, {tenant, [credential], [service], false}} = services_fixture(@tenant)
    platform_service = platform_service_fixture(@tenant)

    assert :ok = TelephonyService.validate(platform_service)

    mixed_services = {:ok, {tenant, [credential], [service, platform_service], false}}
    opts = options(bindings_fixture(@tenant), mixed_services, applications_fixture(@tenant))

    assert {:ok, lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(
               privileged_principal(@tenant),
               @tenant,
               opts
             )

    assert lookups.credential_names == %{
             "deepgram" => ["deepgram"],
             "google" => ["shared"]
           }

    keys = Enum.map(lookups.telephony_services, & &1.key)
    assert "voice" in keys
    assert "support-app" in keys
    assert "platform-voice" in keys

    platform_entry = Enum.find(lookups.telephony_services, &(&1.key == "platform-voice"))
    assert platform_entry == %{key: "platform-voice", name: "platform-voice", provider: "telnyx"}

    assert Enum.all?(lookups.telephony_services, fn entry ->
             Map.keys(entry) |> Enum.sort() == [:key, :name, :provider]
           end)

    dumped = inspect(lookups) <> :erlang.term_to_binary(lookups)
    refute dumped =~ "platform-ingress-1"
    refute dumped =~ "55555555-5555-4555-8555-555555555555"
    refute dumped =~ "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc="

    custom_member = %{privileged_principal(@tenant) | account_kind: :member}

    assert {:ok, custom_lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(custom_member, @tenant, opts)

    assert custom_lookups.credential_names == lookups.credential_names

    assert Enum.map(custom_lookups.telephony_services, & &1.key) |> Enum.sort() ==
             Enum.map(lookups.telephony_services, & &1.key) |> Enum.sort()
  end

  test "privileged lookup sees scoped platform binding with nil ids without secrets" do
    {:ok, {tenant, [credential], [service], false}} = services_fixture(@tenant)

    scoped_platform = %TelephonyService{
      id: "66666666-6666-4666-8666-666666666666",
      tenant_key: @tenant,
      name: "platform-app",
      ingress_key: "platform-app-ingress-secret",
      provider: "telnyx",
      provider_connection_id: "application-platform-app",
      credential_id: nil,
      credential_name: "telnyx",
      credential_owner: :platform,
      public_key: nil,
      outbound_number: nil,
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    assert :ok = TelephonyService.validate(scoped_platform)

    mixed_services = {:ok, {tenant, [credential], [service, scoped_platform], false}}
    opts = options(bindings_fixture(@tenant), mixed_services, applications_fixture(@tenant))

    assert {:ok, lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(
               privileged_principal(@tenant),
               @tenant,
               opts
             )

    keys = Enum.map(lookups.telephony_services, & &1.key)
    assert "voice" in keys
    assert "platform-app" in keys

    assert Enum.all?(lookups.telephony_services, fn entry ->
             Map.keys(entry) |> Enum.sort() == [:key, :name, :provider]
           end)

    dumped = inspect(lookups) <> :erlang.term_to_binary(lookups)
    refute dumped =~ "platform-app-ingress-secret"
    refute dumped =~ "66666666-6666-4666-8666-666666666666"

    assert {:ok, member_lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(member_principal(@tenant), @tenant, opts)

    member_keys = Enum.map(member_lookups.telephony_services, & &1.key)
    assert "voice" in member_keys
    refute "platform-app" in member_keys
  end

  test "member hides platform-owned scoped app present in both services and applications" do
    {:ok, {tenant, [credential], [service], false}} = services_fixture(@tenant)
    {:ok, {_app_tenant, [tenant_app], [], false}} = applications_fixture(@tenant)

    platform_app = %TelephonyService{
      id: "77777777-7777-4777-8777-777777777777",
      tenant_key: @tenant,
      name: "platform-app",
      ingress_key: "platform-app-ingress-secret",
      provider: "telnyx",
      provider_connection_id: "application-platform-app",
      credential_id: nil,
      credential_name: "telnyx",
      credential_owner: :platform,
      public_key: nil,
      outbound_number: nil,
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    assert :ok = TelephonyService.validate(platform_app)

    mixed_services = {:ok, {tenant, [credential], [service, platform_app], false}}

    mixed_applications =
      {:ok, {tenant_fixture(@tenant), [tenant_app, platform_app], [], false}}

    opts = options(bindings_fixture(@tenant), mixed_services, mixed_applications)

    assert {:ok, member_lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(member_principal(@tenant), @tenant, opts)

    member_keys = Enum.map(member_lookups.telephony_services, & &1.key)
    assert "voice" in member_keys
    assert "support-app" in member_keys
    refute "platform-app" in member_keys

    dumped = inspect(member_lookups) <> :erlang.term_to_binary(member_lookups)
    refute dumped =~ "platform-app-ingress-secret"
    refute dumped =~ "77777777-7777-4777-8777-777777777777"

    assert {:ok, privileged_lookups} =
             Vxpipe.Calls.list_call_spec_editor_lookups(
               privileged_principal(@tenant),
               @tenant,
               opts
             )

    privileged_keys = Enum.map(privileged_lookups.telephony_services, & &1.key)
    assert "platform-app" in privileged_keys
  end
end
