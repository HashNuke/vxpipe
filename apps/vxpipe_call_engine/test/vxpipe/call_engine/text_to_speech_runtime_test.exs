defmodule Vxpipe.CallEngine.TextToSpeechRuntimeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.TextToSpeechRuntime
  alias Vxpipe.CallEngine.Usage.ProviderContext

  test "inspection excludes provider and transport credentials" do
    sentinel = "private-runtime-credential"

    assert {:ok, usage_provider} =
             ProviderContext.new(name: "example", integration_id: "voice-profile")

    runtime = %TextToSpeechRuntime{
      provider: {ExampleProvider, %{api_key: sentinel}},
      transport: {ExampleTransport, [authorization: sentinel]},
      maximum_requests: 2,
      asset_cache_identity: %{"voice" => "test-voice"},
      call_id: "call-test",
      participant_id: "participant-test",
      activation_id: "activation-test",
      usage_provider: usage_provider
    }

    inspected = inspect(runtime)

    assert inspected =~ "maximum_requests: 2"
    assert inspected =~ "test-voice"
    refute inspected =~ sentinel
    refute inspected =~ "authorization"
  end
end
