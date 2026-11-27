defmodule Vxpipe.CallEngine.Speech.ConversationLanguagesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.ConversationLanguages

  test "static picker list is curated and shared" do
    tags = ConversationLanguages.supported_tags()

    assert "en" in tags
    assert "en-GB" in tags
    assert "en-US" in tags
    assert "es-MX" in tags
    assert "pt-BR" in tags
    assert Enum.uniq(tags) == tags
    refute "zz" in tags
    assert length(tags) > 50
  end

  test "base-code multi-hint filtering preserves order and deduplicates" do
    assert ConversationLanguages.resolve(
             ["en-GB", "en-US", "es-MX"],
             :stt,
             "elevenlabs",
             "scribe_v2_realtime"
           ) ==
             ["en", "es"]
  end

  test "base-code single-hint receives first supported preference" do
    assert ConversationLanguages.resolve(
             ["en-GB", "en-US", "es-MX"],
             :tts,
             "cartesia",
             "sonic-3"
           ) ==
             ["en"]

    assert ConversationLanguages.resolve(
             ["ja-JP", "es-MX", "en-GB", "en-US", "fr-FR"],
             :tts,
             "cartesia",
             "sonic-3"
           ) == ["ja"]
  end

  test "apply the model limit after filtering unsupported languages and duplicate base codes" do
    prefs = ["ja-JP", "es-MX", "en-GB", "en-US", "fr-FR"]
    assert ConversationLanguages.resolve_supported(prefs, ["en", "es"], false) == ["es"]
    assert ConversationLanguages.resolve_supported(prefs, ["en", "es"], true) == ["es", "en"]
  end

  test "multi-hint preserves preference order after conversion" do
    assert ConversationLanguages.resolve(
             ["ja-JP", "es-MX", "en-GB", "en-US", "fr-FR"],
             :stt,
             "deepgram",
             "flux-general-multi"
           ) == ["ja-JP", "es-MX", "en-GB", "en-US", "fr-FR"]
  end

  test "locale-aware models keep exact wire spelling and cardinality" do
    assert ConversationLanguages.resolve(
             ["en-GB", "en-US", "es-US"],
             :stt,
             "google",
             "gemini-3.5-transcribe-live"
           ) == ["en-GB", "en-US", "es-US"]

    assert ConversationLanguages.resolve(["pt-BR"], :sts, "elevenlabs", "eleven_realtime_v1_mini") ==
             ["pt-br"]
  end

  test "automatic and unmatched preferences omit the parameter" do
    assert ConversationLanguages.resolve([], :stt, "deepgram", "flux-general-multi") == []

    assert ConversationLanguages.resolve(
             ["cmn-Hans-CN"],
             :stt,
             "deepgram",
             "flux-general-multi"
           ) == []

    assert ConversationLanguages.resolve(["en"], :stt, "cartesia", "ink-2") == []
  end

  test "generic language does not imply a specific region" do
    assert ConversationLanguages.resolve(["en"], :tts, "cartesia", "sonic-3.6") == ["en"]
    assert ConversationLanguages.resolve(["en-GB"], :tts, "cartesia", "sonic-3") == ["en"]
  end

  test "flux english omits hints while flux multi serializes them" do
    assert ConversationLanguages.resolve(["en", "es"], :stt, "deepgram", "flux-general-en") == []

    assert ConversationLanguages.resolve(["en"], :stt, "deepgram", "flux-general-multi") ==
             ["en"]
  end

  test "unsupported first preferences are skipped while order is preserved" do
    preferences = ["cmn-Hans-CN", "es-MX", "en-GB", "en-US", "fr-FR"]

    assert ConversationLanguages.resolve(preferences, :stt, "deepgram", "flux-general-multi") ==
             ["es-MX", "en-GB", "en-US", "fr-FR"]

    assert ConversationLanguages.resolve(
             preferences,
             :tts,
             "cartesia",
             "sonic-3"
           ) == ["es"]
  end
end
