defmodule Vxpipe.CallEngine.OpeningAudio.AssetPipelineTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.OpeningAudio.{
    AssetCache,
    AssetLoader,
    Download,
    NetworkAddressPolicy,
    Settings,
    WaveDecoder
  }

  alias Vxpipe.CallEngine.TestOpeningAudioFetcher

  test "decodes only bounded mono 48 kHz PCM16 WAV audio" do
    pcm = <<1, 0, 2, 0, 3, 0, 4, 0>>

    assert {:ok, asset} = WaveDecoder.decode(wave(pcm), maximum_duration_ms: 1_000)
    assert asset.payload == pcm
    assert asset.codec == :linear16
    assert asset.sample_rate == 48_000
    assert asset.channels == 1
    assert asset.byte_order == :little
    assert asset.duration_ms == 0

    assert {:error, :unsupported_audio_format} =
             WaveDecoder.decode(wave(pcm, sample_rate: 16_000), maximum_duration_ms: 1_000)

    assert {:error, :audio_too_long} =
             WaveDecoder.decode(wave(:binary.copy(<<0, 0>>, 48_001)),
               maximum_duration_ms: 1_000
             )
  end

  test "allows only globally routable resolved addresses" do
    for address <- [
          {0, 0, 0, 0},
          {10, 1, 2, 3},
          {100, 64, 0, 1},
          {127, 0, 0, 1},
          {169, 254, 169, 254},
          {172, 16, 0, 1},
          {192, 168, 0, 1},
          {198, 51, 100, 1},
          {0, 0, 0, 0, 0, 0, 0, 1},
          {0xFC00, 0, 0, 0, 0, 0, 0, 1},
          {0xFE80, 0, 0, 0, 0, 0, 0, 1},
          {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1}
        ] do
      refute NetworkAddressPolicy.public_address?(address)
    end

    assert NetworkAddressPolicy.public_address?({8, 8, 8, 8})
    assert NetworkAddressPolicy.public_address?({0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111})

    assert {:error, :unsafe_address} =
             NetworkAddressPolicy.select_public([{8, 8, 8, 8}, {127, 0, 0, 1}])
  end

  test "caches assets by tenant and URL digest without retaining the URL in its key" do
    cache = start_supervised!({AssetCache, maximum_entries: 2, maximum_bytes: 32})
    first = asset(<<1, 0, 2, 0>>)
    second = asset(<<3, 0, 4, 0>>)
    third = asset(<<5, 0, 6, 0>>)

    first_key = AssetCache.key("tenant-one", "https://assets.example.test/notice.wav")
    other_tenant_key = AssetCache.key("tenant-two", "https://assets.example.test/notice.wav")

    assert :miss = AssetCache.fetch(cache, first_key)
    assert :ok = AssetCache.put(cache, first_key, first)
    assert {:ok, ^first} = AssetCache.fetch(cache, first_key)
    assert :miss = AssetCache.fetch(cache, other_tenant_key)

    second_key = AssetCache.key("tenant-one", "https://assets.example.test/second.wav")
    third_key = AssetCache.key("tenant-one", "https://assets.example.test/third.wav")
    assert :ok = AssetCache.put(cache, second_key, second)
    assert :ok = AssetCache.put(cache, third_key, third)

    assert :miss = AssetCache.fetch(cache, first_key)
    assert {:ok, ^second} = AssetCache.fetch(cache, second_key)
    assert {:ok, ^third} = AssetCache.fetch(cache, third_key)

    refute inspect(:sys.get_state(cache)) =~ "assets.example.test"
  end

  test "keys rendered text by tenant and output-affecting text-to-speech identity" do
    identity = %{
      provider: "deepgram_flux",
      model: "voice-one",
      encoding: "linear16",
      sample_rate: 48_000
    }

    key = AssetCache.text_key("tenant-one", "A fixed opening.", identity)

    refute key == AssetCache.text_key("tenant-two", "A fixed opening.", identity)
    refute key == AssetCache.text_key("tenant-one", "A different opening.", identity)

    refute key ==
             AssetCache.text_key("tenant-one", "A fixed opening.", %{
               identity
               | model: "voice-two"
             })

    refute inspect(key) =~ "A fixed opening."
    refute inspect(key) =~ "voice-one"
  end

  test "rejects an unbounded or empty cache configuration" do
    assert {:error, {:invalid_cache_configuration, _child}} =
             start_supervised({AssetCache, maximum_entries: 0, maximum_bytes: 32})

    assert {:error, {:invalid_cache_configuration, _child}} =
             start_supervised({AssetCache, maximum_entries: 2, maximum_bytes: 0})
  end

  test "fetches, validates, and then reuses a tenant-scoped asset" do
    cache = start_supervised!({AssetCache, maximum_entries: 2, maximum_bytes: 256})
    url = "https://assets.example.test/cached.wav"

    assert {:ok, settings} =
             Settings.new(
               cache: cache,
               fetcher:
                 {TestOpeningAudioFetcher,
                  [
                    observer: self(),
                    response:
                      {:ok,
                       %Download{
                         body: wave(<<1, 0, 2, 0>>),
                         content_type: "audio/wav"
                       }}
                  ]},
               maximum_bytes: 256,
               maximum_duration_ms: 1_000,
               timeout_ms: 1_000
             )

    assert {:ok, first} = AssetLoader.load("tenant-one", url, settings)
    assert_receive {:test_opening_audio_fetch, ^url, limits}
    assert limits == [maximum_bytes: 256, timeout_ms: 1_000]

    assert {:ok, ^first} = AssetLoader.load("tenant-one", url, settings)
    refute_receive {:test_opening_audio_fetch, ^url, _limits}

    assert {:ok, ^first} = AssetLoader.load("tenant-two", url, settings)
    assert_receive {:test_opening_audio_fetch, ^url, _limits}
  end

  defp asset(payload) do
    %Vxpipe.CallEngine.OpeningAudio.Asset{
      byte_order: :little,
      channels: 1,
      codec: :linear16,
      duration_ms: div(byte_size(payload), 96),
      payload: payload,
      sample_rate: 48_000
    }
  end

  defp wave(pcm, options \\ []) do
    sample_rate = Keyword.get(options, :sample_rate, 48_000)
    channels = Keyword.get(options, :channels, 1)
    bits_per_sample = Keyword.get(options, :bits_per_sample, 16)
    block_align = div(channels * bits_per_sample, 8)
    byte_rate = sample_rate * block_align

    format =
      <<1::little-16, channels::little-16, sample_rate::little-32, byte_rate::little-32,
        block_align::little-16, bits_per_sample::little-16>>

    body =
      "fmt " <>
        <<byte_size(format)::little-32>> <>
        format <>
        "data" <>
        <<byte_size(pcm)::little-32>> <> pcm

    "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
  end
end
