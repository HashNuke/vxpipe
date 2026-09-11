defmodule Vxpipe.CallEngine.TextToSpeechRuntimeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.TextToSpeechRuntime

  test "inspection excludes provider and transport credentials" do
    sentinel = "private-runtime-credential"

    runtime = %TextToSpeechRuntime{
      provider: {ExampleProvider, %{api_key: sentinel}},
      transport: {ExampleTransport, [authorization: sentinel]},
      maximum_requests: 2,
      asset_cache_identity: %{"voice" => "test-voice"}
    }

    inspected = inspect(runtime)

    assert inspected =~ "maximum_requests: 2"
    assert inspected =~ "test-voice"
    refute inspected =~ sentinel
    refute inspected =~ "authorization"
  end
end
