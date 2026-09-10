defmodule Vxpipe.CallEngine.RemoteMCP.IdentityChurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.RemoteMCPIdentityProbe

  @churn_count 100
  @max_runtime_growth 5

  @tag timeout: 120_000
  test "runtime binding churn does not create identities as atoms or modules" do
    assert %{atom_growth: atom_growth, module_growth: module_growth, atomized_values: []} =
             measure_identity_churn()

    assert atom_growth <= @max_runtime_growth
    assert module_growth <= @max_runtime_growth
  end

  defp measure_identity_churn do
    args = [~c"-pa" | :code.get_path()]
    {:ok, peer, _node} = :peer.start_link(%{connection: :standard_io, args: args})

    try do
      _startup_measurement =
        :peer.call(peer, RemoteMCPIdentityProbe, :measure, [@churn_count, 0], 60_000)

      :peer.call(
        peer,
        RemoteMCPIdentityProbe,
        :measure,
        [@churn_count, 2 * @churn_count],
        60_000
      )
    after
      :peer.stop(peer)
    end
  end
end
