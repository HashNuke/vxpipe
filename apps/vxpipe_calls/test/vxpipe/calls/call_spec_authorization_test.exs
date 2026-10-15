defmodule Vxpipe.Calls.CallSpecAuthorizationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{InstallationOperator, Principal}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  test "machine discovery and selected-tenant checks share the admin scope requirement" do
    admin = %Principal{
      tenant_key: @tenant,
      api_key_id: "tenant-key",
      scopes: MapSet.new([:admin])
    }

    calls = %{admin | scopes: MapSet.new([:calls])}

    platform = %InstallationOperator{
      grant: :installation_operator,
      credential_kind: :platform_api_key,
      api_key_id: "platform-key"
    }

    for action <- [:read, :write] do
      assert :ok = Calls.authorize_call_specs(admin, action)
      assert :ok = Calls.authorize_call_specs(admin, action, @tenant)

      assert {:error, :tenant_access_forbidden} =
               Calls.authorize_call_specs(admin, action, @other)

      assert {:error, :insufficient_scope} = Calls.authorize_call_specs(calls, action)
      assert {:error, :insufficient_scope} = Calls.authorize_call_specs(calls, action, @tenant)
      assert :ok = Calls.authorize_call_specs(platform, action)
      assert :ok = Calls.authorize_call_specs(platform, action, @other)
      assert {:error, :invalid_tenant_key} = Calls.authorize_call_specs(platform, action, "bad")
    end

    assert {:error, :authoring_authority_required} = Calls.authorize_call_specs(admin, :unknown)

    assert {:error, :authoring_authority_required} =
             Calls.authorize_call_specs(admin, :unknown, @tenant)
  end

  test "discovery excludes legacy and internal installation actors while existing domain access remains" do
    for operator <- [
          InstallationOperator.authority(),
          %InstallationOperator{
            grant: :installation_operator,
            credential_kind: :legacy_operator_api_key
          }
        ] do
      assert {:error, :authoring_authority_required} = Calls.authorize_call_specs(operator, :read)
      assert :ok = Calls.authorize_call_specs(operator, :read, @tenant)
      assert :ok = Calls.authorize_call_specs(operator, :write, @tenant)
    end

    for unknown <- [nil, %{}, %InstallationOperator{grant: :invalid}] do
      assert {:error, :authoring_authority_required} = Calls.authorize_call_specs(unknown, :read)

      assert {:error, :authoring_authority_required} =
               Calls.authorize_call_specs(unknown, :read, @tenant)
    end
  end

  test "browser reads and writes retain their exact grants and membership caps" do
    reader = %UserPrincipal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["call_specs.read", "call_specs.write"]),
      assigned_tenants: %{@tenant => :read},
      all_tenant_actions: MapSet.new()
    }

    assert :ok = Calls.authorize_call_specs(reader, :read, @tenant)
    assert {:error, :forbidden} = Calls.authorize_call_specs(reader, :write, @tenant)
    assert {:error, :forbidden} = Calls.authorize_call_specs(reader, :read, @other)
    writer = %{reader | assigned_tenants: %{@tenant => :read_write}}
    assert :ok = Calls.authorize_call_specs(writer, :write, @tenant)

    assert {:error, :forbidden} =
             Calls.authorize_call_specs(
               %{writer | grants: MapSet.new(["calls.read"])},
               :read,
               @tenant
             )

    assert {:error, :authoring_authority_required} = Calls.authorize_call_specs(writer, :read)
  end
end
