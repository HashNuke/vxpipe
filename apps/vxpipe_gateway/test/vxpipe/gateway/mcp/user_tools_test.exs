defmodule Vxpipe.Gateway.MCP.UserToolsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.MCP.{AccountTools, CallSpecTools, CallTools}
  alias Vxpipe.Gateway.Test.AccountStore
  alias Vxpipe.Identity.Principal

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  test "call tools require effective calls.write rather than an account kind" do
    writer = principal(~w(calls.read calls.write))
    assert names(CallTools.list(writer)) == ~w(create_call create_join_token hangup_call)
    assert {:ok, _} = CallTools.authorize(writer, "create_call", call_args())

    for reader <- [
          %{writer | grants: MapSet.new(["calls.read"])},
          %{writer | assigned_tenants: %{@tenant => :read}},
          %{writer | assigned_tenants: %{}},
          %{writer | account_kind: :superadmin, grants: MapSet.new()}
        ] do
      assert CallTools.list(reader) == []
      assert {:error, :forbidden} = CallTools.authorize(reader, "create_call", call_args())
      assert {:error, :forbidden} = CallTools.call(reader, "create_call", call_args(), [])
    end

    assert {:error, :forbidden} =
             CallTools.call(writer, "create_call", Map.put(call_args(), "tenant_key", @other), [])

    all_tenants = %{writer | assigned_tenants: %{}, all_tenant_actions: writer.grants}
    assert names(CallTools.list(all_tenants)) == names(CallTools.list(writer))
  end

  test "call-spec discovery separates reads from writes and honors membership caps" do
    reader = principal(~w(call_specs.read call_specs.write), :read)
    read_names = ~w(list_call_specs get_call_spec list_providers list_provider_models)
    assert names(CallSpecTools.list(reader)) == read_names

    assert {:ok, _} =
             CallSpecTools.authorize(reader, "list_call_specs", %{"tenant_key" => @tenant})

    write_args = %{"tenant_key" => @tenant, "call_spec_definition" => %{}}
    assert {:error, :forbidden} = CallSpecTools.authorize(reader, "create_call_spec", write_args)
    assert {:error, :forbidden} = CallSpecTools.call(reader, "create_call_spec", write_args, [])

    writer = %{reader | assigned_tenants: %{@tenant => :read_write}}
    assert length(CallSpecTools.list(writer)) == 7
    assert {:ok, _} = CallSpecTools.authorize(writer, "create_call_spec", write_args)

    assert {:error, :forbidden} =
             CallSpecTools.call(
               writer,
               "create_call_spec",
               Map.put(write_args, "tenant_key", @other),
               []
             )

    assert CallSpecTools.list(%{reader | assigned_tenants: %{}}) == []
    assert CallSpecTools.list(principal(~w(calls.read calls.write))) == []
  end

  test "account readers see and invoke safe directories without mutation tools" do
    reader = principal(~w(users.read))
    assert names(AccountTools.list(reader)) == ~w(list_users list_role_options)

    for name <- ~w(list_users list_role_options) do
      assert {:ok, args} = AccountTools.authorize(reader, name, %{})
      assert {:ok, %{items: [_]}} = AccountTools.call(reader, name, args, options())
    end

    assert {:error, :forbidden} = AccountTools.authorize(reader, "create_user", user_args())
    assert {:error, :forbidden} = AccountTools.call(reader, "create_user", user_args(), options())

    assert {:error, :forbidden} =
             AccountTools.authorize(reader, "disable_user", %{"user_id" => AccountStore.user_id()})

    refute_received {:account_create, _}
    refute_received {:account_update, _}
  end

  test "account writes follow category grants and keep user attribution" do
    admin = %{principal(~w(users.read users.members.write)) | account_kind: :admin}
    assert length(AccountTools.list(admin)) == 5
    assert {:ok, args} = AccountTools.authorize(admin, "create_user", user_args())
    assert {:ok, _} = AccountTools.call(admin, "create_user", args, options())
    assert_received {:account_create, attrs}
    assert attrs.actor_user_public_id == admin.user_public_id
    assert attrs.actor_session_public_id == admin.session_public_id
    refute Map.has_key?(attrs, :actor_api_key_public_id)

    for name <- ~w(update_user disable_user) do
      assert {:ok, _} =
               AccountTools.authorize(admin, name, %{"user_id" => AccountStore.user_id()})
    end

    reduced = %{admin | grants: MapSet.new(["users.read"])}
    assert names(AccountTools.list(reduced)) == ~w(list_users list_role_options)
    assert AccountTools.list(%{admin | grants: MapSet.new()}) == []
  end

  test "OAuth tools respect the approved tenant ceiling even for an administrator" do
    grants = ~w(calls.read calls.write call_specs.read call_specs.write users.read)
    actor = principal(grants)

    delegated = %{
      actor
      | account_kind: :admin,
        session_public_id: nil,
        credential_kind: :oauth,
        oauth_grant_public_id: "33333333-3333-4333-8333-333333333333",
        assigned_tenants: %{},
        all_tenant_actions: MapSet.new(grants),
        delegation: %{
          assigned_tenants: %{@tenant => :read},
          all_tenant_actions: MapSet.new()
        }
    }

    assert CallTools.list(delegated) == []

    assert names(CallSpecTools.list(delegated)) ==
             ~w(list_call_specs get_call_spec list_providers list_provider_models)

    assert names(AccountTools.list(delegated)) == ~w(list_users list_role_options)

    assert {:error, :forbidden} =
             CallTools.authorize(delegated, "create_call", call_args())

    assert {:error, :forbidden} =
             CallSpecTools.call(delegated, "list_call_specs", %{"tenant_key" => @other}, [])

    assert {:ok, args} = AccountTools.authorize(delegated, "list_users", %{})
    assert {:ok, %{items: [_]}} = AccountTools.call(delegated, "list_users", args, options())
  end

  defp principal(grants, access \\ :read_write) do
    %Principal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: :member,
      grants: MapSet.new(grants),
      assigned_tenants: %{@tenant => access},
      all_tenant_actions: MapSet.new()
    }
  end

  defp call_args, do: %{"tenant_key" => @tenant, "call_spec_id" => "spec"}
  defp names(tools), do: Enum.map(tools, & &1.name)
  defp options, do: [identity_dependencies: AccountStore.dependencies()]

  defp user_args,
    do: %{
      "email" => "member@example.test",
      "role_id" => AccountStore.role_id(),
      "password" => "long test password",
      "password_confirmation" => "long test password"
    }
end
