defmodule Vxpipe.Gateway.Test.MCPOAuth do
  @moduledoc false
  alias Vxpipe.Identity.{Permission, Principal}

  def actor(tenant \\ "AAAAAAAAAAAAAAAA", access \\ :calls) do
    grants = grants(access)
    all = if access == :platform, do: grants, else: MapSet.new()
    assigned = if access == :platform, do: %{}, else: %{tenant => :read_write}

    %Principal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: nil,
      oauth_grant_public_id: "22222222-2222-4222-8222-222222222222",
      credential_kind: :oauth,
      account_kind: if(access == :platform, do: :superadmin, else: :member),
      grants: grants,
      assigned_tenants: assigned,
      all_tenant_actions: all,
      delegation: %{assigned_tenants: assigned, all_tenant_actions: all}
    }
  end

  defp grants(:platform), do: Permission.builtin_grants(:superadmin)
  defp grants(:calls), do: MapSet.new(~w(calls.read calls.write))
  defp grants(:specs), do: MapSet.new(~w(call_specs.read call_specs.write))
  defp grants(:full), do: MapSet.union(grants(:calls), grants(:specs))
end
