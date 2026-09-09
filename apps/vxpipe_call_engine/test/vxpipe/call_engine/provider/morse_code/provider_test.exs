defmodule Vxpipe.CallEngine.Provider.MorseCode.ProviderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.{MorseCodeSTT, MorseCodeTTS}
  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal, as: STTSignal
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal, as: TTSSignal

  test "MorseCodeSTT exposes local configuration and normalized signals" do
    assert {:ok, %Config{} = config} = MorseCodeSTT.new(sample_rate: 16_000)
    assert MorseCodeSTT.connection_options(config) == %{config: config}
    refute Map.has_key?(MorseCodeSTT.connection_options(config), :url)
    assert MorseCodeSTT.media_format(config) == %{codec: :linear16, sample_rate: 16_000}

    assert {:ok,
            %STTSignal{
              kind: :turn_started,
              provider_sequence: 1,
              provider_turn_index: 0,
              request_id: "morse-local",
              text: ""
            }} =
             MorseCodeSTT.decode(
               JSON.encode!(%{
                 "type" => "TurnInfo",
                 "event" => "StartOfTurn",
                 "sequence_id" => 1,
                 "turn_index" => 0,
                 "request_id" => "morse-local",
                 "transcript" => ""
               })
             )

    assert {:ok, %STTSignal{kind: :turn_ended, text: "SOS", trigger: "morse_end_gap"}} =
             MorseCodeSTT.decode(
               JSON.encode!(%{
                 "type" => "TurnInfo",
                 "event" => "EndOfTurn",
                 "sequence_id" => 2,
                 "turn_index" => 0,
                 "request_id" => "morse-local",
                 "transcript" => "SOS",
                 "trigger" => "morse_end_gap"
               })
             )

    assert {:error, :invalid_configuration} = MorseCodeSTT.new(sample_rate: 44_100)
    assert {:error, :invalid_message} = MorseCodeSTT.decode(~s({"type":"TurnInfo"}))
    assert {:error, :invalid_json} = MorseCodeSTT.decode("not-json")
  end

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
