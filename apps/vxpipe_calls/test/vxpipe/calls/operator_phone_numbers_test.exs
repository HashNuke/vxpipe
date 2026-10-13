defmodule Vxpipe.Calls.OperatorPhoneNumbersTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    InstallationOperator,
    OperatorPhoneNumbers,
    Tenant,
    TestPhoneNumberAssignments,
    TestTelephonyServiceRepository
  }

  alias Vxpipe.Calls.{ResolvedProviderCredential, ResolvedTelephonyService, TelephonyService}
  alias Vxpipe.Identity.Principal, as: UserPrincipal
  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"
  test "authorized inventory annotates current publications and permits the same call spec's number" do
    tenant = %Tenant{key: @tenant, name: "Example", inserted_at: DateTime.utc_now()}

    reader = fn snapshot, query ->
      assert snapshot.service.tenant_key == @tenant
      assert query.search == "555"
      {:ok, %{numbers: [%{id: "1", number: "+15550000001", name: "Office"}], next_page: "2"}}
    end

    options = [
      telephony_service_repository: TestTelephonyServiceRepository.repository([tenant]),
      call_spec_repository:
        {TestPhoneNumberAssignments,
         {@tenant, [%{number: "+15550000001", call_spec_id: "other", name: "Reception"}]}},
      number_reader: reader
    ]

    query = %{search: "555", page: nil, call_spec_id: nil}

    assert {:ok, %{numbers: [%{available: false, assigned_to: ["Reception"]}], next_page: "2"}} =
             OperatorPhoneNumbers.list(
               InstallationOperator.authority(),
               @tenant,
               "primary-phone",
               query,
               options
             )

    assert {:ok, %{numbers: [%{available: true, assigned_to: []}]}} =
             OperatorPhoneNumbers.list(
               InstallationOperator.authority(),
               @tenant,
               "primary-phone",
               %{query | call_spec_id: "other"},
               options
             )
  end

  test "unauthorized and malformed requests do not activate the provider" do
    assert {:error, :installation_operator_required} =
             OperatorPhoneNumbers.list(nil, @tenant, "phone", %{}, [])

    assert {:error, :invalid_request} =
             OperatorPhoneNumbers.list(
               InstallationOperator.authority(),
               @tenant,
               "phone",
               %{search: String.duplicate("x", 65), page: nil},
               []
             )
  end

  test "assigned call spec author lists tenant numbers without tenant_services.read" do
    tenant = %Tenant{key: @tenant, name: "Example", inserted_at: DateTime.utc_now()}

    reader = fn snapshot, query ->
      assert snapshot.service.tenant_key == @tenant
      assert query.search == "555"
      {:ok, %{numbers: [%{id: "1", number: "+15550000001", name: "Office"}], next_page: nil}}
    end

    options = [
      telephony_service_repository: TestTelephonyServiceRepository.repository([tenant]),
      call_spec_repository: {TestPhoneNumberAssignments, {@tenant, []}},
      number_reader: reader
    ]

    query = %{search: "555", page: nil, call_spec_id: nil}
    member = member_principal(@tenant)

    assert {:ok, %{numbers: [%{available: true, assigned_to: []}], next_page: nil}} =
             OperatorPhoneNumbers.list(member, @tenant, "primary-phone", query, options)

    dumped =
      inspect(OperatorPhoneNumbers.list(member, @tenant, "primary-phone", query, options))

    refute dumped =~ "fixture-phone-private-marker"

    no_grant = member_principal(@tenant, ["calls.read"])

    assert {:error, :forbidden} =
             OperatorPhoneNumbers.list(no_grant, @tenant, "primary-phone", query, options)

    read_only = member_principal(@tenant, ["call_specs.read"])

    assert {:error, :forbidden} =
             OperatorPhoneNumbers.list(read_only, @tenant, "primary-phone", query, options)

    foreign = member_principal(@other)

    assert {:error, :forbidden} =
             OperatorPhoneNumbers.list(foreign, @tenant, "primary-phone", query, options)

    assert {:error, :invalid_tenant_key} =
             OperatorPhoneNumbers.list(member, "bad", "primary-phone", query, options)
  end

  test "member cannot list platform-owned numbers without use_platform_services" do
    platform_snapshot = platform_telnyx_snapshot(@tenant, "platform-voice")
    tenant_snapshot = tenant_legacy_snapshot(@tenant, "tenant-voice")

    repository =
      {__MODULE__.PlatformRepo,
       %{
         tenant: @tenant,
         snapshots: %{
           "platform-voice" => platform_snapshot,
           "tenant-voice" => tenant_snapshot
         }
       }}

    reader = fn _snapshot, _query ->
      {:ok, %{numbers: [%{id: "1", number: "+15550000001", name: "Office"}], next_page: nil}}
    end

    base_options = [
      call_spec_repository: {TestPhoneNumberAssignments, {@tenant, []}},
      number_reader: reader
    ]

    query = %{search: "", page: nil, call_spec_id: nil}
    member = member_principal(@tenant)
    privileged = privileged_principal(@tenant)

    assert {:ok, %{numbers: _}} =
             OperatorPhoneNumbers.list(
               member,
               @tenant,
               "tenant-voice",
               query,
               [telephony_service_repository: repository] ++ base_options
             )

    assert {:error, :phone_numbers_unavailable} =
             OperatorPhoneNumbers.list(
               member,
               @tenant,
               "platform-voice",
               query,
               [telephony_service_repository: repository] ++ base_options
             )

    assert {:ok, %{numbers: _}} =
             OperatorPhoneNumbers.list(
               privileged,
               @tenant,
               "platform-voice",
               query,
               [telephony_service_repository: repository] ++ base_options
             )
  end

  defmodule PlatformRepo do
    def resolve(%{tenant: tenant, snapshots: snapshots}, tenant, name) do
      case Map.fetch(snapshots, name) do
        {:ok, snapshot} -> {:ok, snapshot}
        :error -> {:error, :telephony_service_not_found}
      end
    end

    def resolve(_context, _tenant, _name), do: {:error, :telephony_service_not_found}
  end

  defp member_principal(tenant, grants \\ ["call_specs.read", "call_specs.write"]) do
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
        MapSet.new(["call_specs.read", "call_specs.write", "call_specs.use_platform_services"]),
      assigned_tenants: %{tenant => :read_write},
      all_tenant_actions: MapSet.new()
    }
  end

  defp tenant_legacy_snapshot(tenant_key, name) do
    credential_id = "66666666-6666-4666-8666-666666666666"
    public_key = Base.encode64(:binary.copy(<<1>>, 32))

    service = %TelephonyService{
      id: "77777777-7777-4777-8777-777777777777",
      tenant_key: tenant_key,
      name: name,
      ingress_key: "ingress-secret",
      provider: "telnyx",
      provider_connection_id: "connection-tenant",
      credential_id: credential_id,
      credential_name: nil,
      credential_owner: nil,
      public_key: public_key,
      outbound_number: "+14155550200",
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    credential = %Vxpipe.Calls.ProviderCredential{
      id: credential_id,
      tenant_key: tenant_key,
      provider: "telnyx",
      name: "voice",
      auth_kind: "api_key"
    }

    %ResolvedTelephonyService{
      service: service,
      credential: %ResolvedProviderCredential{
        credential: credential,
        payload: %{"api_key" => "fixture-phone-private-marker"}
      }
    }
  end

  defp platform_telnyx_snapshot(tenant_key, name) do
    credential_id = "55555555-5555-4555-8555-555555555555"
    public_key = Base.encode64(:binary.copy(<<2>>, 32))

    service = %TelephonyService{
      id: "88888888-8888-4888-8888-888888888888",
      tenant_key: tenant_key,
      name: name,
      ingress_key: "ingress-secret",
      provider: "telnyx",
      provider_connection_id: "connection-platform",
      credential_id: credential_id,
      credential_name: "telnyx",
      credential_owner: :platform,
      public_key: public_key,
      outbound_number: "+14155550200",
      answering_machine_detection: :disabled,
      media_token_ttl_ms: 60_000,
      webhook_tolerance_seconds: 300
    }

    credential = %Vxpipe.Calls.ProviderCredential{
      id: credential_id,
      tenant_key: nil,
      owner: :platform,
      provider: "telnyx",
      name: "telnyx",
      auth_kind: "api_key"
    }

    %ResolvedTelephonyService{
      service: service,
      credential: %ResolvedProviderCredential{
        credential: credential,
        payload: %{
          "api_key" => "fixture-phone-private-marker",
          "public_key" => public_key
        }
      }
    }
  end
end
