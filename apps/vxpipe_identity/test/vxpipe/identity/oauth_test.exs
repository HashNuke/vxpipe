defmodule Vxpipe.Identity.OAuthTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Vxpipe.Identity.{FakeOAuthStore, OAuth, Principal}

  @resource "https://example.test/mcp"
  @user "11111111-1111-4111-8111-111111111111"
  @role "22222222-2222-4222-8222-222222222222"
  @grant "33333333-3333-4333-8333-333333333333"

  setup do
    for key <- [:oauth_store, :oauth_browser_store] do
      previous = Application.fetch_env(:vxpipe_identity, key)
      Application.put_env(:vxpipe_identity, key, FakeOAuthStore)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:vxpipe_identity, key, value)
          :error -> Application.delete_env(:vxpipe_identity, key)
        end
      end)
    end

    :ok
  end

  test "credential operations use only their configured port and preserve resource and snapshot binding" do
    operations = [
      {:register_client, [%{"client_name" => "Example"}], {:ok, %{client_id: "client"}}},
      {:consent_snapshot, [:principal], {:ok, %{authorization_version: 1}}},
      {:issue_code, [:principal, %{"state" => "state"}, @resource, %{authorization_version: 1}],
       {:ok, %{code: "code"}}},
      {:exchange, [%{"code" => "code"}, @resource], {:ok, %{access_token: "token"}}},
      {:revoke, [%{"token" => "token"}, @resource], :ok},
      {:rate_limit, [:token, "127.0.0.1"], :ok}
    ]

    for {operation, args, response} <- operations do
      Process.put({FakeOAuthStore, :response}, response)
      assert apply(OAuth, operation, args) == response
      assert_received {:oauth_store, ^operation, ^args}
    end
  end

  test "browser operations use the separate browser port without losing browser binding or principal" do
    operations = [
      {:begin_authorization, [%{"client_id" => "client"}, @resource, "binding"],
       {:ok, String.duplicate("t", 43)}},
      {:consent, ["transaction", "binding", :principal], {:ok, %{client_name: "Example"}}},
      {:complete_authorization, ["transaction", "binding", :principal, :approve],
       {:ok, %{code: "code"}}},
      {:complete_authorization, ["transaction", "binding", :principal, :deny],
       {:ok, %{error: "access_denied"}}},
      {:list_grants, [:principal], {:ok, [%{grant_id: @grant}]}},
      {:revoke_grant, [:principal, @grant], :ok}
    ]

    for {operation, args, response} <- operations do
      Process.put({FakeOAuthStore, :response}, response)
      assert apply(OAuth, operation, args) == response
      assert_received {:oauth_store, ^operation, ^args}
    end

    Application.delete_env(:vxpipe_identity, :oauth_browser_store)
    assert OAuth.list_grants(:principal) == {:error, :unavailable}
    Process.put({FakeOAuthStore, :response}, :ok)
    assert OAuth.revoke(%{}, @resource) == :ok
  end

  test "authentication constructs explicit delegated authority from trusted records" do
    Process.put({FakeOAuthStore, :response}, {:ok, identity()})
    assert {:ok, %Principal{} = principal} = OAuth.authenticate("synthetic-access", @resource)
    assert_received {:oauth_store, :authenticate, ["synthetic-access", @resource]}
    assert principal.credential_kind == :oauth
    assert principal.session_public_id == nil
    assert principal.oauth_grant_public_id == @grant
    assert principal.user_public_id == @user
    assert principal.grants == MapSet.new(["calls.read"])
    assert principal.delegation.assigned_tenants == %{"AAAAAAAAAAAAAAAA" => :read}

    Process.put(
      {FakeOAuthStore, :response},
      {:ok, %{identity() | user: %{identity().user | authorization_version: 2}}}
    )

    assert OAuth.authenticate("synthetic-access", @resource) == {:error, :invalid_token}
    Process.put({FakeOAuthStore, :response}, {:ok, principal})
    assert OAuth.authenticate("synthetic-access", @resource) == {:error, :unavailable}
  end

  test "missing ports and unknown adapter failures fail closed without diagnostics containing credentials" do
    for key <- [:oauth_store, :oauth_browser_store] do
      Application.delete_env(:vxpipe_identity, key)
    end

    assert OAuth.exchange(%{}, @resource) == {:error, :unavailable}
    assert OAuth.authenticate("synthetic-access", @resource) == {:error, :unavailable}
    assert OAuth.begin_authorization(%{}, @resource, "binding") == {:error, :unavailable}
    Application.put_env(:vxpipe_identity, :oauth_store, FakeOAuthStore)

    log =
      capture_log(fn ->
        for response <- [
              :raise,
              :exit,
              :throw,
              {:error, %{secret: "private-oauth-sentinel"}},
              {:error, :unknown_storage_failure},
              :unexpected
            ] do
          Process.put({FakeOAuthStore, :response}, response)
          assert OAuth.exchange(%{}, @resource) == {:error, :unavailable}
          assert OAuth.authenticate("synthetic-access", @resource) == {:error, :unavailable}
        end

        Process.put({FakeOAuthStore, :response}, {:ok, %{user: %{}, role: %{}, grant: %{}}})
        assert OAuth.authenticate("synthetic-access", @resource) == {:error, :unavailable}
      end)

    refute log =~ "private-oauth-sentinel"
  end

  test "known protocol and browser errors are preserved as atoms" do
    for reason <- [
          :invalid_request,
          :invalid_client_metadata,
          :invalid_grant,
          :invalid_token,
          :invalid_session,
          :invalid_scope,
          :invalid_target,
          :unsupported_grant_type,
          :rate_limited,
          :quota_exceeded,
          :not_found,
          :unavailable
        ] do
      Process.put({FakeOAuthStore, :response}, {:error, reason})
      assert OAuth.exchange(%{}, @resource) == {:error, reason}
      assert OAuth.consent("id", "binding", :principal) == {:error, reason}
    end
  end

  defp identity do
    %{
      user: %{
        public_id: @user,
        disabled_at: nil,
        authorization_version: 1,
        role_public_id: @role,
        memberships: %{"AAAAAAAAAAAAAAAA" => :read_write}
      },
      role: %{
        public_id: @role,
        revision: 1,
        kind: :member,
        grants: [
          %{permission: "calls.read", scope: :assigned_tenants},
          %{permission: "calls.write", scope: :assigned_tenants}
        ]
      },
      grant: %{
        public_id: @grant,
        user_public_id: @user,
        authorization_version: 1,
        role_public_id: @role,
        role_revision: 1,
        authority: %{
          "grants" => ["calls.read"],
          "assigned_tenants" => %{"AAAAAAAAAAAAAAAA" => "read"},
          "all_tenant_actions" => []
        }
      }
    }
  end
end
