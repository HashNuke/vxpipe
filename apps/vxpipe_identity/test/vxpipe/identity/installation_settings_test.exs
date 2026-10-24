defmodule Vxpipe.Identity.InstallationSettingsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Identity.{InstallationSettings, Principal}

  def fetch, do: {:ok, %{setup_completed_at: ~U[2026-10-24 00:00:00Z]}}

  test "legacy installation adapters remain readable and report unsupported writes as unavailable" do
    actor = struct(Principal, account_kind: :superadmin, credential_kind: :browser_session)
    deps = %{installations: __MODULE__}
    assert {:ok, %{public_url: nil, revision: 0}} = InstallationSettings.fetch(deps, actor)
    assert {:error, :unavailable} = InstallationSettings.update(deps, actor, "https://calls.example.test", 0)
  end
end
