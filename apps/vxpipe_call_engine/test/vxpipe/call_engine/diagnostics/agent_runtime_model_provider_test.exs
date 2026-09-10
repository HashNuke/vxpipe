defmodule Vxpipe.CallEngine.Diagnostics.AgentRuntimeModelProviderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelResponse}

  alias Vxpipe.CallEngine.Diagnostics.{AgentRuntimeModelProvider, ModelFixture}

  test "streams the configured local fixture response through the neutral provider contract" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Fixture answer."}
      )

    assert {:ok, config} =
             AgentRuntimeModelProvider.new(fixture: fixture, model: "test:scripted")

    assert inspect(config) =~ "test:scripted"
    refute inspect(config) =~ inspect(fixture)

    request = request("Hello fixture")

    assert {:ok, %ModelResponse{text: "Fixture answer."}} =
             AgentRuntimeModelProvider.stream(config, request, fn text ->
               send(self(), {:fixture_delta, text})
               :ok
             end)

    assert_receive {:fixture_delta, "Fixture answer."}
    status = ModelFixture.status(fixture)
    assert status.next_scenario == :success
  end

  test "normalizes fixture failures and missing output without inventing an answer" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Fixture answer."}
      )

    assert {:ok, config} =
             AgentRuntimeModelProvider.new(fixture: fixture, model: "test:scripted")

    assert :ok = ModelFixture.arm(fixture, :failure)

    assert {:error, :provider_unavailable} =
             AgentRuntimeModelProvider.stream(config, request("Fail"), fn _text -> :ok end)

    assert :ok = ModelFixture.arm(fixture, :missing)

    assert {:error, :invalid_provider_response} =
             AgentRuntimeModelProvider.stream(config, request("Missing"), fn _text -> :ok end)
  end

  defp request(input) do
    ModelRequest.new(
      [Message.system("Answer briefly."), Message.user(input)],
      [],
      [],
      %{request_id: "fixture-request"}
    )
  end
end
