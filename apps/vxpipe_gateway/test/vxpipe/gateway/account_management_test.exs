defmodule Vxpipe.Gateway.AccountManagementTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Gateway.{AccountJSON, AccountManagement}
  alias Vxpipe.Gateway.Test.AccountStore

  test "MCP discovery admits only a verified platform-key actor with a public key identifier" do
    assert :ok = AccountManagement.authorize_machine(actor())

    for denied <- [
          InstallationOperator.authority(),
          %{actor() | api_key_id: "invalid"},
          %Vxpipe.Identity.Principal{
            user_public_id: AccountStore.user_id(),
            session_public_id: AccountStore.key_id(),
            account_kind: :superadmin,
            grants: MapSet.new(["users.read"])
          }
        ] do
      assert {:error, :forbidden} = AccountManagement.authorize_machine(denied)
    end
  end

  test "verified platform actor reaches narrow Identity account operations with trusted attribution" do
    assert {:ok, user} = AccountManagement.create_user(actor(), input(), options())
    assert_received {:account_create, attrs}
    assert attrs.actor_api_key_public_id == AccountStore.key_id()
    refute Map.has_key?(attrs, :actor_user_public_id)
    refute Map.has_key?(user, :password_hash)

    assert {:ok, _} =
             AccountManagement.update_user(
               actor(),
               user.public_id,
               %{"email" => "changed@example.test"},
               options()
             )

    assert_received {:account_update, attrs}
    refute Map.has_key?(attrs, :disabled)
    refute Map.has_key?(attrs, :memberships)

    assert {:ok, disabled} = AccountManagement.disable_user(actor(), user.public_id, options())
    assert disabled.disabled_at
    assert_received {:account_update, %{disabled: true}}
  end

  test "account workflow rejects legacy or tenant authority and invalid canonical input before store writes" do
    for denied <- [
          InstallationOperator.authority(),
          %{api_key_id: AccountStore.key_id()},
          %Vxpipe.Calls.Principal{
            api_key_id: "tenant",
            tenant_key: "AAAAAAAAAAAAAAAA",
            scopes: MapSet.new([:admin, :calls])
          }
        ] do
      assert {:error, :forbidden} = AccountManagement.create_user(denied, input(), options())
    end

    assert {:error, :invalid_account} =
             AccountManagement.create_user(
               actor(),
               Map.put(input(), "actor_api_key_public_id", "forged"),
               options()
             )

    assert {:error, :invalid_account} =
             AccountManagement.update_user(
               actor(),
               AccountStore.user_id(),
               %{"password" => "not-supported"},
               options()
             )

    refute_received {:account_create, _}
    refute_received {:account_update, _}
  end

  test "safe HTTP and MCP projections share bounded account and role directories" do
    assert {:ok, page} =
             AccountManagement.list_users(
               actor(),
               %{"page_size" => "1", "query" => "member"},
               options()
             )

    assert_received {:account_query, %{page_size: 1, search: "member"}}

    assert %{
             users: [%{id: _, roleId: _, memberships: [%{tenantId: _}]}],
             pagination: %{page_size: 1}
           } = AccountJSON.user_page(page, :http)

    assert %{items: [%{user_id: _, role_id: _, memberships: [%{tenant_key: _}]}]} =
             AccountJSON.user_page(page, :mcp)

    refute inspect(AccountJSON.user_page(page, :mcp)) =~ "private-password-hash"

    assert {:error, :invalid_pagination} =
             AccountManagement.list_users(actor(), %{"page_size" => 51}, options())

    assert {:error, :invalid_account} =
             AccountManagement.list_role_options(actor(), %{"query" => "ignored"}, options())

    assert {:ok, roles} = AccountManagement.list_role_options(actor(), %{}, options())

    assert %{roles: [%{id: _, kind: nil}], pagination: %{page_size: 25}} =
             AccountJSON.role_page(roles, :http)

    refute inspect(AccountJSON.role_page(roles, :mcp)) =~ "grants"
  end

  defp actor,
    do: %InstallationOperator{
      grant: :installation_operator,
      api_key_id: AccountStore.key_id(),
      credential_kind: :platform_api_key
    }

  defp options, do: [identity_dependencies: AccountStore.dependencies()]

  defp input,
    do: %{
      "email" => "member@example.test",
      "role_id" => AccountStore.role_id(),
      "password" => "long test password",
      "password_confirmation" => "long test password"
    }
end
