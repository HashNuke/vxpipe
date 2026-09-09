defmodule Vxpipe.CallEngine.Diagnostics.ModelFixtureTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Diagnostics.ModelFixture

  test "arms one controlled outcome and then returns to the configured default" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Local fixture response."}
      )

    assert %{next_scenario: :success, delay_ms: 0} = ModelFixture.status(fixture)
    assert :ok = ModelFixture.arm(fixture, :failure)
    assert %{next_scenario: :failure} = ModelFixture.status(fixture)

    assert {:ok, %{scenario: :failure, user: "hello"}} = ModelFixture.take(fixture, "hello")
    assert %{next_scenario: :success} = ModelFixture.status(fixture)

    assert {:ok, %{scenario: :success, response: "Local fixture response."}} =
             ModelFixture.take(fixture, "again")
  end

  test "rejects scenarios outside the fixed diagnostic set" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Local fixture response."}
      )

    assert {:error, :invalid_scenario} = ModelFixture.arm(fixture, :arbitrary)
    assert %{next_scenario: :success} = ModelFixture.status(fixture)
  end
end
