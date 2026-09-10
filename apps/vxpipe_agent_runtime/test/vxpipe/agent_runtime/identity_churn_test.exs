defmodule Vxpipe.AgentRuntime.IdentityChurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.IdentityProbe

  @churn_count 250
  @maximum_runtime_growth 5

  @tag timeout: 120_000
  test "unique tool aliases and schemas do not create proportional atoms or modules" do
    assert %{atom_growth: atom_growth, module_growth: module_growth, atomized_values: []} =
             measure_identity_churn()

    assert atom_growth <= @maximum_runtime_growth
    assert module_growth <= @maximum_runtime_growth
  end

  defp measure_identity_churn do
    args = [~c"-pa" | :code.get_path()]
    {:ok, peer, _node} = :peer.start_link(%{connection: :standard_io, args: args})

    try do
      _startup_measurement = :peer.call(peer, IdentityProbe, :measure, [@churn_count, 0], 30_000)

      :peer.call(
        peer,
        IdentityProbe,
        :measure,
        [@churn_count, 2 * @churn_count],
        30_000
      )
    after
      :peer.stop(peer)
    end
  end
end
