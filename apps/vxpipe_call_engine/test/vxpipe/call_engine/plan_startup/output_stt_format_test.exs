defmodule Vxpipe.CallEngine.PlanStartup.OutputSTTFormatTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.PlanStartup.OutputSTTFormat
  alias Vxpipe.Providers.Google
  alias Vxpipe.Providers.MorseCode

  test "actual Google output, not its microphone input, is compared with recognizer input" do
    assert {:ok, generator} = Google.STSSession.configure([])
    assert {:ok, recognizer} = Google.STTSession.configure([])
    assert generator.input_format == recognizer.format
    assert generator.format.sample_rate == 24_000
    assert recognizer.format.sample_rate == 16_000

    assert {:error, :incompatible_output_stt_format} =
             OutputSTTFormat.validate_descriptors(generator, recognizer)

    assert {:ok, matching} = MorseCode.STTSession.configure(sample_rate: 24_000)
    assert :ok = OutputSTTFormat.validate_descriptors(generator, matching)
  end

  test "full validated format is required including shape, encoding, channels and PCM details" do
    assert {:ok, generator} = MorseCode.STSSession.configure(sample_rate: 16_000)
    assert {:ok, recognizer} = Google.STTSession.configure([])
    assert :ok = OutputSTTFormat.validate_descriptors(generator, recognizer)

    opus = %{
      recognizer
      | format: %{encoding: :opus, container: :raw, channels: 1, sample_rate: 16_000}
    }

    assert :ok = Vxpipe.CallEngine.Speech.Descriptor.validate(opus)

    assert {:error, :incompatible_output_stt_format} =
             OutputSTTFormat.validate_descriptors(generator, opus)

    for {key, value} <- [
          sample_rate: 8_000,
          encoding: :opus,
          channels: 2,
          container: :wav,
          byte_order: :big,
          signed?: false
        ] do
      mismatched = %{recognizer | format: Map.put(recognizer.format, key, value)}

      assert {:error, :incompatible_output_stt_format} =
               OutputSTTFormat.validate_descriptors(generator, mismatched)
    end

    invalid = Map.put(generator.format, :channels, 2)

    assert {:error, :incompatible_output_stt_format} =
             OutputSTTFormat.validate_descriptors(
               %{generator | format: invalid},
               %{recognizer | format: invalid}
             )

    assert {:error, :incompatible_output_stt_format} =
             OutputSTTFormat.validate_descriptors(recognizer, generator)
  end
end
