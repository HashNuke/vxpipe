defmodule Vxpipe.CallEngine.Provider.MorseCode.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.MorseCode.{Alphabet, Config, Decoder, Encoder}

  @itu_ascii_symbols %{
    "A" => ".-",
    "B" => "-...",
    "C" => "-.-.",
    "D" => "-..",
    "E" => ".",
    "F" => "..-.",
    "G" => "--.",
    "H" => "....",
    "I" => "..",
    "J" => ".---",
    "K" => "-.-",
    "L" => ".-..",
    "M" => "--",
    "N" => "-.",
    "O" => "---",
    "P" => ".--.",
    "Q" => "--.-",
    "R" => ".-.",
    "S" => "...",
    "T" => "-",
    "U" => "..-",
    "V" => "...-",
    "W" => ".--",
    "X" => "-..-",
    "Y" => "-.--",
    "Z" => "--..",
    "0" => "-----",
    "1" => ".----",
    "2" => "..---",
    "3" => "...--",
    "4" => "....-",
    "5" => ".....",
    "6" => "-....",
    "7" => "--...",
    "8" => "---..",
    "9" => "----.",
    "." => ".-.-.-",
    "," => "--..--",
    ":" => "---...",
    "?" => "..--..",
    "'" => ".----.",
    "-" => "-....-",
    "/" => "-..-.",
    "(" => "-.--.",
    ")" => "-.--.-",
    "\"" => ".-..-.",
    "=" => "-...-",
    "+" => ".-.-.",
    "@" => ".--.-."
  }

  @reference_runs [
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 3},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 3},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 7},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 1},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 14}
  ]

  test "encodes normalized text with ITU mark and spacing ratios" do
    assert {:ok, config} = Config.new()
    assert {:ok, pcm} = Encoder.encode(config, "  et\tA\n")

    assert pcm_runs(pcm, config) == [
             {:tone, 1},
             {:silence, 3},
             {:tone, 3},
             {:silence, 7},
             {:tone, 1},
             {:silence, 1},
             {:tone, 3},
             {:silence, 14}
           ]

    assert byte_size(pcm) == 33 * unit_samples(config) * 2
  end

  test "incrementally decodes an independent known SOS 2 PCM fixture" do
    assert {:ok, config} = Config.new()
    assert {:ok, decoder} = Decoder.new(config)

    pcm = reference_pcm(@reference_runs, config)
    chunks = split_repeatedly(pcm, [1, 319, 47, 641, 2_003])

    {decoder, events} =
      Enum.reduce(chunks, {decoder, []}, fn chunk, {decoder, events} ->
        assert {:ok, decoder, emitted} = Decoder.push(decoder, chunk)
        {decoder, events ++ emitted}
      end)

    assert {:ok, _decoder, []} = Decoder.flush(decoder)
    assert Enum.count(events, &(&1 == :started)) == 1
    assert List.last(events) == {:final, "SOS 2"}
  end

  test "matches every directly represented ASCII signal in the ITU table" do
    assert Alphabet.characters() == @itu_ascii_symbols |> Map.keys() |> Enum.sort()

    Enum.each(@itu_ascii_symbols, fn {character, signal} ->
      assert Alphabet.encode(character) == {:ok, signal}
      assert Alphabet.decode(signal) == {:ok, character}
    end)
  end

  test "rejects invalid configuration and bounded encoder input explicitly" do
    assert {:error, :invalid_configuration} = Config.new(sample_rate: 44_100)
    assert {:error, :invalid_configuration} = Config.new(frequency_hz: 8_000)
    assert {:error, :invalid_configuration} = Config.new(detection_threshold: 4_096)
    assert {:error, :invalid_configuration} = Config.new(unit_duration_ms: 61)
    assert {:error, :invalid_configuration} = Config.new(maximum_audio_bytes: 16_777_217)

    assert {:ok, config} = Config.new()
    assert {:error, :empty_text} = Encoder.encode(config, " \t\n")
    assert {:error, :unsupported_character} = Encoder.encode(config, "%")
    assert {:error, :invalid_text} = Encoder.encode(config, <<255>>)
    assert {:error, :invalid_text} = Encoder.encode(config, :not_text)

    assert {:ok, short_input} = Config.new(maximum_text_bytes: 2)
    assert {:error, :input_too_large} = Encoder.encode(short_input, "ABC")

    assert {:ok, tiny_output} = Config.new(maximum_audio_bytes: 1)
    assert {:error, :output_too_large} = Encoder.encode(tiny_output, "E")
  end

  test "flushes a valid final mark once and never fabricates silence" do
    assert {:ok, config} = Config.new()
    assert {:ok, decoder} = Decoder.new(config)

    tone = reference_pcm([{:tone, 1}], config)
    assert {:ok, decoder, [:started]} = Decoder.push(decoder, tone)
    assert {:ok, decoder, [{:partial, "E"}, {:final, "E"}]} = Decoder.flush(decoder)
    assert {:ok, _decoder, []} = Decoder.flush(decoder)

    assert {:ok, decoder} = Decoder.new(config)
    silence = reference_pcm([{:silence, 20}], config)
    assert {:ok, decoder, []} = Decoder.push(decoder, silence)
    assert {:ok, _decoder, []} = Decoder.flush(decoder)
  end

  test "rejects malformed PCM, unsupported timing, frequency and symbols" do
    assert {:ok, config} = Config.new()
    assert {:ok, decoder} = Decoder.new(config)
    assert {:error, :invalid_audio} = Decoder.push(decoder, :not_audio)
    assert {:ok, decoder, []} = Decoder.push(decoder, <<0>>)
    assert {:error, :incomplete_sample} = Decoder.flush(decoder)

    assert {:ok, decoder} = Decoder.new(config)
    two_unit_tone = reference_pcm([{:tone, 2}], config)
    assert {:ok, decoder, [:started]} = Decoder.push(decoder, two_unit_tone)
    assert {:error, :invalid_timing} = Decoder.flush(decoder)

    assert {:ok, decoder} = Decoder.new(config)
    wrong_frequency = reference_pcm([{:tone, 1}], %{config | frequency_hz: 1_200})
    assert {:error, :unsupported_frequency} = Decoder.push(decoder, wrong_frequency)

    assert {:ok, decoder} = Decoder.new(config)

    unsupported_signal =
      reference_pcm(
        Enum.intersperse(List.duplicate({:tone, 1}, 8), {:silence, 1}),
        config
      )

    assert {:ok, decoder, [:started]} = Decoder.push(decoder, unsupported_signal)
    assert {:error, :unsupported_signal} = Decoder.flush(decoder)
  end

  test "bounds an undecided input signal" do
    assert {:ok, config} = Config.new(maximum_utterance_ms: 840)
    assert {:ok, decoder} = Decoder.new(config)
    oversized_silence = reference_pcm([{:silence, 15}], config)

    assert {:error, :signal_too_long} = Decoder.push(decoder, oversized_silence)
  end

  test "accepts one analysis window of timing tolerance" do
    assert {:ok, config} = Config.new()
    assert {:ok, decoder} = Decoder.new(config)

    short_dot = reference_window_pcm(:tone, 5, config)
    assert {:ok, decoder, [:started]} = Decoder.push(decoder, short_dot)
    assert {:ok, _decoder, [{:partial, "E"}, {:final, "E"}]} = Decoder.flush(decoder)

    assert {:ok, decoder} = Decoder.new(config)
    too_short = reference_window_pcm(:tone, 4, config)
    assert {:ok, decoder, [:started]} = Decoder.push(decoder, too_short)
    assert {:error, :invalid_timing} = Decoder.flush(decoder)
  end

  defp pcm_runs(pcm, config) do
    bytes_per_unit = unit_samples(config) * 2

    pcm
    |> split_fixed(bytes_per_unit)
    |> Enum.map(fn unit ->
      if unit == :binary.copy(<<0, 0>>, unit_samples(config)), do: :silence, else: :tone
    end)
    |> Enum.reduce([], fn
      kind, [{kind, units} | rest] -> [{kind, units + 1} | rest]
      kind, runs -> [{kind, 1} | runs]
    end)
    |> Enum.reverse()
  end

  defp reference_pcm(runs, config) do
    runs
    |> Enum.map(fn
      {:tone, units} -> reference_tone(units * unit_samples(config), config)
      {:silence, units} -> :binary.copy(<<0, 0>>, units * unit_samples(config))
    end)
    |> IO.iodata_to_binary()
  end

  defp reference_tone(sample_count, config) do
    period = div(config.sample_rate, config.frequency_hz)
    half_period = max(div(period, 2), 1)

    for sample_index <- 0..(sample_count - 1), into: <<>> do
      sample = if rem(div(sample_index, half_period), 2) == 0, do: 3_000, else: -3_000
      <<sample::signed-little-16>>
    end
  end

  defp reference_window_pcm(:tone, windows, config) do
    samples_per_window = div(config.sample_rate * config.window_duration_ms, 1_000)
    reference_tone(windows * samples_per_window, config)
  end

  defp split_fixed(<<>>, _size), do: []

  defp split_fixed(binary, size) when byte_size(binary) >= size do
    <<chunk::binary-size(size), rest::binary>> = binary
    [chunk | split_fixed(rest, size)]
  end

  defp split_repeatedly(binary, sizes), do: split_repeatedly(binary, sizes, sizes, [])

  defp split_repeatedly(<<>>, _remaining_sizes, _all_sizes, chunks),
    do: Enum.reverse(chunks)

  defp split_repeatedly(binary, [], all_sizes, chunks),
    do: split_repeatedly(binary, all_sizes, all_sizes, chunks)

  defp split_repeatedly(binary, [size | sizes], all_sizes, chunks)
       when byte_size(binary) > size do
    <<chunk::binary-size(size), rest::binary>> = binary
    split_repeatedly(rest, sizes, all_sizes, [chunk | chunks])
  end

  defp split_repeatedly(binary, _sizes, _all_sizes, chunks),
    do: Enum.reverse([binary | chunks])

  defp unit_samples(config), do: div(config.sample_rate * config.unit_duration_ms, 1_000)
end
