defmodule Vxpipe.CallEngine.Speech.ConversationLanguagesScribeMandarinTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.ConversationLanguages

  @v2 "scribe_v2_realtime"
  @v3 "scribe_v3_live"

  test "scribe translates Mandarin preferences to zh before filtering" do
    for model <- [@v2, @v3] do
      assert ConversationLanguages.resolve(["cmn-Hans-CN"], :stt, "elevenlabs", model) == ["zh"]
      assert ConversationLanguages.resolve(["cmn-TW"], :stt, "elevenlabs", model) == ["zh"]
      assert ConversationLanguages.resolve(["zh-CN"], :stt, "elevenlabs", model) == ["zh"]
    end
  end

  test "scribe keeps Cantonese yue separate from Mandarin zh" do
    for model <- [@v2, @v3] do
      assert ConversationLanguages.resolve(["yue-Hant-HK"], :stt, "elevenlabs", model) == ["yue"]
      assert ConversationLanguages.resolve(["yue"], :stt, "elevenlabs", model) == ["yue"]

      assert ConversationLanguages.resolve(
               ["cmn-Hans-CN", "yue-Hant-HK"],
               :stt,
               "elevenlabs",
               model
             ) == ["zh", "yue"]
    end
  end

  test "scribe Mandarin translation is scoped to scribe only" do
    assert ConversationLanguages.resolve(
             ["cmn-Hans-CN"],
             :stt,
             "deepgram",
             "flux-general-multi"
           ) == []

    assert ConversationLanguages.resolve(["cmn-Hans-CN"], :tts, "rime", "coda") == []
  end
end
