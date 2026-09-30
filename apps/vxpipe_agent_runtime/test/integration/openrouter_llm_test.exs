defmodule Vxpipe.AgentRuntime.Integration.OpenRouterLLMTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_openrouter
  @moduletag timeout: 90_000
  @moduletag capture_log: true

  test "streamed tool call, continuation and reported usage" do
    assert :ok = Vxpipe.AgentRuntime.LiveLLMContract.run("openrouter")
  end
end
