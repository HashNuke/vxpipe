defmodule Vxpipe.Providers.Deepgram.VoiceSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CapabilityCatalog, CallSpec.CapabilitySelection}
  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech

  test "a call spec selects a Flux voice while Deepgram builds the wire model" do
    assert {:ok, selection} =
             CapabilitySelection.new(
               %{
                 provider: "deepgram",
                 model: "flux",
                 options: %{voice: "haley", encoding: "linear16", sample_rate: 24_000}
               },
               :text_to_speech,
               ["text_to_speech"]
             )

    assert {:ok, options} = CapabilityCatalog.speech_options(selection)
    assert options[:model] == "flux-haley-en"
    assert {:ok, config} = FluxTextToSpeech.new(Keyword.put(options, :api_key, "synthetic-key"))

    assert URI.parse(FluxTextToSpeech.connection_options(config).url).query =~
             "model=flux-haley-en"
  end

  test "a Flux family selection requires a valid voice" do
    for options <- [%{}, %{voice: ""}, %{voice: "haley&model=other"}] do
      assert {:error, _reason} =
               CapabilitySelection.new(
                 %{provider: "deepgram", model: "flux", options: options},
                 :text_to_speech,
                 ["text_to_speech"]
               )
    end
  end

  test "a voice selection uses the provider's supported audio defaults" do
    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "deepgram", model: "flux", options: %{voice: "hannah"}},
               :text_to_speech,
               ["text_to_speech"]
             )

    assert {:ok, options} = CapabilityCatalog.speech_options(selection)
    assert options[:model] == "flux-hannah-en"
    assert options[:encoding] == :linear16
    assert {:ok, descriptor} = Vxpipe.Providers.Deepgram.TTSSession.configure(options)
    assert descriptor.format.sample_rate == 48_000
  end

  test "an explicit model remains valid but cannot be combined with a voice override" do
    explicit = %{
      provider: "deepgram",
      model: "flux-haley-en",
      options: %{encoding: "linear16", sample_rate: 24_000}
    }

    assert {:ok, selection} =
             CapabilitySelection.new(explicit, :text_to_speech, ["text_to_speech"])

    assert {:ok, options} = CapabilityCatalog.speech_options(selection)
    assert options[:model] == "flux-haley-en"

    assert {:error, _reason} =
             explicit
             |> put_in([:options, :voice], "hannah")
             |> CapabilitySelection.new(:text_to_speech, ["text_to_speech"])
  end
end
