defmodule Vxpipe.Calls.TestDashboardRepository do
  @moduledoc false

  def tenant_candidates({_owner, tenant, _calls}, {:keys, [key]}, 1) do
    {:ok, if(tenant.key == key, do: [tenant], else: [])}
  end

  def recent_calls({owner, _tenant, calls}, key, limit) do
    send(owner, {:recent_calls, key, limit})
    calls
  end
end
