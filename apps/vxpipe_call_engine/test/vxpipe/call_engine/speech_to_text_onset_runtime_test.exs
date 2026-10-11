defmodule Vxpipe.CallEngine.SpeechToTextOnsetRuntimeTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.ConversationalSTT
  alias Vxpipe.CallEngine.{CapabilityCatalog, SpeechToTextRuntime}

  test "new human selections compose default transcript onset and explicit VAD without changing identity" do
    for vad <- [false, true] do
      assert {:ok, selection} =
               CapabilitySelection.new(
                 %{provider: "morse", model: "morse", vad: vad},
                 :speech_to_text,
                 ["speech_to_text"]
               )

      assert {:ok, selected, private} = SpeechToTextRuntime.provider({MorseSession, []}, [])

      assert {:ok, {ConversationalSTT, options}, composed_private} =
               SpeechToTextRuntime.conversation(selection, selected, private)

      assert Keyword.get(options, :provider) == MorseSession
      assert Keyword.get(options, :vad) == vad
      assert Keyword.get(composed_private, :recognizer) == MorseSession
      assert {:ok, descriptor} = ConversationalSTT.configure(options)
      assert descriptor.usage_identity.provider == :morse_code
      assert descriptor.endpointing == :provider_gap
      assert descriptor.settings.vad == vad
      refute descriptor.finite_input?
      historical = Map.delete(selection, :vad)

      assert {:ok, ^selected, ^private} =
               SpeechToTextRuntime.conversation(historical, selected, private)
    end
  end

  test "new human Scribe uses VAD commits while pinned historical and output selections retain manual settings" do
    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "elevenlabs", model: "scribe_v2_realtime"},
               :speech_to_text,
               ["speech_to_text"]
             )

    assert {:ok, new_options} = CapabilityCatalog.speech_options(selection)
    assert Keyword.get(new_options, :commit_strategy) == :vad
    assert {:ok, historical} = CapabilityCatalog.speech_options(Map.delete(selection, :vad))
    assert Keyword.get(historical, :commit_strategy) == :manual

    assert {:ok, output} =
             CapabilitySelection.new(
               %{provider: "elevenlabs", model: "scribe_v2_realtime"},
               :output_speech_to_text,
               ["output_speech_to_text"]
             )

    assert {:ok, output_options} = CapabilityCatalog.speech_options(output)
    assert Keyword.get(output_options, :commit_strategy) == :manual
  end
end
