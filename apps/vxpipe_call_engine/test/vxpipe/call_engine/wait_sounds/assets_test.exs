defmodule Vxpipe.CallEngine.WaitSounds.AssetsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.WaitSounds
  alias Vxpipe.CallEngine.OpeningAudio.{AssetCache, Download, Settings}
  alias Vxpipe.CallEngine.TestOpeningAudioFetcher
  alias Vxpipe.CallEngine.WaitSounds.Assets

  test "bundled defaults normalize once, share immutable audio, and include an audible finite cue" do
    settings = settings({:error, :must_not_fetch})
    assert {:ok, prepared} = Assets.prepare("tenant", %WaitSounds{}, settings)
    assert map_size(prepared.assets) == 3
    assert prepared.slots.call_setup == prepared.slots.transfer_to_human
    assert prepared.slots.transfer_to_agent == prepared.slots.transfer_joining
    ring = Map.fetch!(prepared.assets, prepared.slots.call_setup)
    assert ring.channels == 1
    assert ring.sample_rate == 48_000
    assert ring.duration_ms == 9_000
    assert byte_size(ring.payload) == 864_000
    cue = Map.fetch!(prepared.assets, prepared.connection_cue)
    assert cue.duration_ms == 250

    peak =
      for <<sample::little-signed-16 <- cue.payload>>, reduce: 0 do
        peak -> max(peak, abs(sample))
      end

    assert peak in 16_000..16_500
    refute_receive {:test_opening_audio_fetch, _, _}
  end

  test "silenced waits retain the mandatory cue" do
    assert {:ok, sounds} = WaitSounds.from_optional({:ok, nil})
    assert {:ok, prepared} = Assets.prepare("tenant", sounds, settings({:error, :must_not_fetch}))
    assert map_size(prepared.assets) == 1
    assert Enum.all?(prepared.slots, fn {_slot, digest} -> is_nil(digest) end)
    assert Map.has_key?(prepared.assets, prepared.connection_cue)
  end

  test "fetches a shared stereo URL once, normalizes without clipping, and scopes cached bytes to tenant" do
    pcm =
      <<32_767::little-signed-16, 32_767::little-signed-16, -32_768::little-signed-16,
        -32_768::little-signed-16, 100::little-signed-16, -100::little-signed-16>>

    settings = settings({:ok, %Download{body: wave(pcm, 2), content_type: "audio/wav"}})
    url = "http://media.example.com/shared.wav?version=1"

    sounds = %WaitSounds{
      call_setup: nil,
      transfer_to_agent: url,
      transfer_to_human: url,
      transfer_joining: nil
    }

    assert {:ok, prepared} = Assets.prepare("one", sounds, settings)
    assert_receive {:test_opening_audio_fetch, ^url, _}
    refute_receive {:test_opening_audio_fetch, _, _}
    asset = Map.fetch!(prepared.assets, prepared.slots.transfer_to_agent)

    assert asset.payload ==
             <<32_767::little-signed-16, -32_768::little-signed-16, 0::little-signed-16>>

    assert prepared.slots.transfer_to_agent == prepared.slots.transfer_to_human
    assert {:ok, ^prepared} = Assets.prepare("one", sounds, settings)
    refute_receive {:test_opening_audio_fetch, _, _}
    assert {:ok, _} = Assets.prepare("two", sounds, settings)
    assert_receive {:test_opening_audio_fetch, ^url, _}
    refute inspect(prepared) =~ "media.example.com"
  end

  test "later preparation can refresh a URL without mutating an earlier call's pinned audio" do
    first_settings =
      settings({:ok, %Download{body: wave(<<1::little-16>>, 1), content_type: "audio/wav"}})

    second_settings = %{
      first_settings
      | fetcher:
          {TestOpeningAudioFetcher,
           [
             observer: self(),
             response:
               {:ok, %Download{body: wave(<<2::little-16>>, 1), content_type: "audio/wav"}}
           ]}
    }

    sounds = %WaitSounds{
      call_setup: "https://media.example.com/change.wav",
      transfer_to_agent: nil,
      transfer_to_human: nil,
      transfer_joining: nil
    }

    assert {:ok, first} = Assets.prepare("one", sounds, first_settings)
    assert {:ok, second} = Assets.prepare("one", sounds, second_settings, maximum_age_ms: 0)
    refute first.slots.call_setup == second.slots.call_setup
    assert Map.fetch!(first.assets, first.slots.call_setup).payload == <<1::little-16>>
    assert Map.fetch!(second.assets, second.slots.call_setup).payload == <<2::little-16>>
  end

  test "invalid custom files fail at the slot without substituting bundled audio" do
    sounds = %WaitSounds{
      call_setup: nil,
      transfer_to_agent: nil,
      transfer_to_human: nil,
      transfer_joining: "https://media.example.com/bad.wav"
    }

    for response <- [
          {:error, :download_failed},
          {:ok, %Download{body: "invalid", content_type: "audio/wav"}},
          {:ok, %Download{body: wave(<<0::little-16>>, 1), content_type: "text/plain"}},
          {:ok, %Download{body: wave(<<0::little-16>>, 2), content_type: "audio/wav"}}
        ] do
      assert {:error, %{details: %{"path" => ["wait_sounds", "transfer_joining"]}}} =
               Assets.prepare("one", sounds, settings(response))
    end

    oversized =
      {:ok, %Download{body: wave(:binary.copy(<<0>>, 1_728_004), 2), content_type: "audio/wav"}}

    limited = %{settings(oversized) | maximum_duration_ms: 9_000}
    assert {:error, _} = Assets.prepare("one", sounds, limited)
    limited = %{settings(oversized) | maximum_bytes: 1_728_044}
    assert {:error, _} = Assets.prepare("one", sounds, limited)
  end

  defp settings(response) do
    cache =
      start_supervised!({AssetCache, maximum_entries: 8, maximum_bytes: 8_388_608},
        id: make_ref()
      )

    assert {:ok, settings} =
             Settings.new(
               cache: cache,
               fetcher: {TestOpeningAudioFetcher, [observer: self(), response: response]}
             )

    settings
  end

  defp wave(pcm, channels) do
    format =
      <<1::little-16, channels::little-16, 48_000::little-32, 96_000 * channels::little-32,
        2 * channels::little-16, 16::little-16>>

    body = "fmt " <> <<16::little-32>> <> format <> "data" <> <<byte_size(pcm)::little-32>> <> pcm
    "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
  end
end
