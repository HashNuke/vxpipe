defmodule Vxpipe.CallEngine.Provider.MorseCode.ProviderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS
  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal, as: TTSSignal

  test "MorseCodeTTS uses the ordinary speech control and audio contract" do
    assert {:ok, %Config{} = config} = MorseCodeTTS.new(sample_rate: 16_000)
    assert MorseCodeTTS.connection_options(config) == %{config: config}
    refute Map.has_key?(MorseCodeTTS.connection_options(config), :url)

    assert MorseCodeTTS.media_format(config) == %{
             codec: :linear16,
             sample_rate: 16_000,
             channels: 1,
             byte_order: :little
           }

    assert JSON.decode!(MorseCodeTTS.encode_speak("SOS")) == %{
             "type" => "Speak",
             "text" => "SOS"
           }

    assert JSON.decode!(MorseCodeTTS.encode_flush()) == %{"type" => "Flush"}

    assert JSON.decode!(MorseCodeTTS.encode_interrupt(120)) == %{
             "type" => "Interrupt",
             "playback_offset_ms" => 120
           }

    assert {:ok, %TTSSignal{kind: :speech_started, provider_speech_id: "morse-1"}} =
             MorseCodeTTS.decode(~s({"type":"SpeechStarted","speech_id":"morse-1"}))

    assert {:ok, %TTSSignal{kind: :speech_completed, provider_speech_id: "morse-1"}} =
             MorseCodeTTS.decode(~s({"type":"SpeechMetadata","speech_id":"morse-1"}))

    assert {:ok,
            %TTSSignal{
              kind: :speech_interrupted,
              provider_speech_id: "morse-1",
              audio_played_ms: 120,
              text_spoken: "",
              text_remaining: "SOS"
            }} =
             MorseCodeTTS.decode(
               ~s({"type":"SpeechInterrupted","speech_id":"morse-1","audio_played_ms":120,"text_spoken":"","text_remaining":"SOS"})
             )

    assert {:audio, <<1, 0, 2, 0>>} = MorseCodeTTS.decode_audio(<<1, 0, 2, 0>>)
    assert {:error, :empty_audio} = MorseCodeTTS.decode_audio(<<>>)

    assert {:error, :audio_too_large} =
             MorseCodeTTS.decode_audio(:binary.copy(<<0>>, 65_537))
  end
end
