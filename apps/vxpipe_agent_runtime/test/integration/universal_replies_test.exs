defmodule Vxpipe.AgentRuntime.Integration.UniversalRepliesTest do
  use ExUnit.Case, async: false

  @moduletag :live_providers
  @moduletag timeout: 600_000
  @moduletag capture_log: true

  for streaming <- [false, true] do
    @tag :live_gemini
    @tag :live_universal_auto
    test "google native explicit AUTO conversation streaming=#{streaming}" do
      Vxpipe.AgentRuntime.LiveUniversalConversation.run(
        "google",
        unquote(streaming),
        :google_object,
        tool_choice: :auto
      )
    end
  end

  for streaming <- [false, true] do
    @tag :live_gemini
    @tag :live_universal_portable
    @tag :live_universal_replies
    test "google portable receptionist conversation streaming=#{streaming}" do
      Vxpipe.AgentRuntime.LiveUniversalConversation.run(
        "google",
        unquote(streaming),
        :portable_json
      )
    end
  end

  for {provider, tag} <- Vxpipe.AgentRuntime.LiveUniversalConversation.providers(),
      streaming <- [false, true] do
    @tag tag
    @tag :live_universal_replies
    if provider in ["deepseek", "fireworks", "openrouter"] do
      @tag :live_universal_remaining
    end

    test "#{provider} modern receptionist conversation streaming=#{streaming}" do
      Vxpipe.AgentRuntime.LiveUniversalConversation.run(unquote(provider), unquote(streaming))
    end
  end
end
