defmodule Vxpipe.Calls.OperatorPhoneNumbersTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{InstallationOperator, OperatorPhoneNumbers, Tenant, TestPhoneNumberAssignments, TestTelephonyServiceRepository}
  @tenant "AAAAAAAAAAAAAAAA"
  test "authorized inventory annotates current publications and permits the same call spec's number" do
    tenant = %Tenant{key: @tenant, name: "Example", inserted_at: DateTime.utc_now()}
    reader = fn snapshot, query ->
      assert snapshot.service.tenant_key == @tenant
      assert query.search == "555"
      {:ok, %{numbers: [%{id: "1", number: "+15550000001", name: "Office"}], next_page: "2"}}
    end
    options = [telephony_service_repository: TestTelephonyServiceRepository.repository([tenant]),
      call_spec_repository: {TestPhoneNumberAssignments, {@tenant, [%{number: "+15550000001", call_spec_id: "other", name: "Reception"}]}}, number_reader: reader]
    query = %{search: "555", page: nil, call_spec_id: nil}
    assert {:ok, %{numbers: [%{available: false, assigned_to: ["Reception"]}], next_page: "2"}} = OperatorPhoneNumbers.list(InstallationOperator.authority(), @tenant, "primary-phone", query, options)
    assert {:ok, %{numbers: [%{available: true, assigned_to: []}]}} = OperatorPhoneNumbers.list(InstallationOperator.authority(), @tenant, "primary-phone", %{query | call_spec_id: "other"}, options)
  end
  test "unauthorized and malformed requests do not activate the provider" do
    assert {:error, :installation_operator_required} = OperatorPhoneNumbers.list(nil, @tenant, "phone", %{}, [])
    assert {:error, :invalid_request} = OperatorPhoneNumbers.list(InstallationOperator.authority(), @tenant, "phone", %{search: String.duplicate("x", 65), page: nil}, [])
  end
end
