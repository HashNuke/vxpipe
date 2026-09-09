defmodule Vxpipe.CallEngine.Provider.MorseCode.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}

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
