defmodule Vxpipe.Identity.DiagnosticsSettingsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Identity.{DiagnosticsSettings, Principal}

  def fetch(actor) do
    send(self(), {:settings_read, actor.user_public_id})
    {:ok, %{enabled: false, revision: 0, updated_at: nil, updated_by: nil}}
  end

  def update(actor, enabled, revision) do
    send(self(), {:settings_write, actor.user_public_id, enabled, revision})
    {:error, :conflict}
  end

  test "built-in admin and superadmin browser sessions can read the default-off setting" do
    for kind <- [:admin, :superadmin] do
      actor = actor(kind)
      assert {:ok, %{enabled: false, revision: 0}} = DiagnosticsSettings.fetch(deps(), actor)
      assert_received {:settings_read, "user"}
    end
  end

  test "member, custom-role, delegated, OAuth and machine authority cannot read or change it" do
    invalid = [
      actor(:member),
      actor(:custom),
      %{actor(:admin) | credential_kind: :oauth, session_public_id: nil},
      %{actor(:admin) | delegation: %{}},
      %{actor(:admin) | oauth_grant_public_id: "grant"},
      %{actor(:admin) | session_public_id: nil},
      %{actor(:admin) | user_public_id: ""},
      %{account_kind: :admin, credential_kind: :browser_session},
      nil
    ]

    for authority <- invalid do
      assert {:error, :forbidden} = DiagnosticsSettings.fetch(deps(), authority)
      assert {:error, :forbidden} = DiagnosticsSettings.update(deps(), authority, true, 0)
    end

    refute_received {:settings_read, _}
    refute_received {:settings_write, _, _, _}
  end

  test "writes accept only a boolean and a bounded persisted revision" do
    for {enabled, revision, reason} <- [
          {"true", 0, :invalid_enabled},
          {nil, 0, :invalid_enabled},
          {true, -1, :invalid_revision},
          {true, "0", :invalid_revision},
          {true, 9_223_372_036_854_775_807, :invalid_revision}
        ] do
      assert {:error, ^reason} =
               DiagnosticsSettings.update(deps(), actor(:admin), enabled, revision)
    end

    refute_received {:settings_write, _, _, _}
  end

  test "writes preserve the expected revision and propagate a stale-save conflict" do
    assert {:error, :conflict} =
             DiagnosticsSettings.update(deps(), actor(:admin), true, 3)

    assert_received {:settings_write, "user", true, 3}
  end

  test "an absent port reports unavailable rather than inventing enabled authority" do
    assert {:error, :unavailable} = DiagnosticsSettings.fetch(%{}, actor(:admin))
    assert {:error, :unavailable} = DiagnosticsSettings.update(%{}, actor(:admin), true, 0)
  end

  defp deps, do: %{diagnostics_settings: __MODULE__}

  defp actor(kind),
    do:
      struct(Principal, account_kind: kind, user_public_id: "user", session_public_id: "session")
end
