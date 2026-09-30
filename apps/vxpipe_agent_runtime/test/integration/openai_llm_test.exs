defmodule Vxpipe.AgentRuntime.Integration.OpenAILLMTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_openai
  @moduletag timeout: 90_000
  @moduletag capture_log: true

  test "streamed tool call, continuation and reported usage" do
    assert :ok = Vxpipe.AgentRuntime.LiveLLMContract.run("openai")
  end
end
