defmodule Vxpipe.Providers.Deepgram.LiveFixtureTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Deepgram.LiveFixture

  test "generates a brief PCM answer once and reuses it without transcoding" do
    root = Path.join(System.tmp_dir!(), "vxpipe-deepgram-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    audio = :binary.copy(<<1, 0>>, 8_000)
    observer = self()

    assert :ok =
             LiveFixture.ensure_short!(
               root: root,
               request: fn ->
                 send(observer, :short_fixture_requested)
                 {:ok, audio}
               end
             )

    assert_received :short_fixture_requested
    assert File.read!(LiveFixture.short_pcm_path(root)) == audio

    assert :ok =
             LiveFixture.ensure_short!(
               root: root,
               request: fn -> flunk("the saved short sample must be reused") end
             )
  end

  test "generated speech carries two seconds of PCM silence for streaming turn detection" do
    root = Path.join(System.tmp_dir!(), "vxpipe-deepgram-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    speech = <<1, 0, 2, 0>>

    assert :ok =
             LiveFixture.ensure!(
               root: root,
               request: fn -> {:ok, speech} end,
               transcode: fn _, opus ->
                 File.write!(opus, "OggSfixture")
                 :ok
               end
             )

    assert File.read!(LiveFixture.pcm_path(root)) == speech <> :binary.copy(<<0>>, 64_000)
  end

  test "generates both samples once and reuses them" do
    root = Path.join(System.tmp_dir!(), "vxpipe-deepgram-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    request = fn ->
      send(self(), :tts_requested)
      {:ok, <<0, 0, 1, 0, 2, 0, 3, 0>>}
    end

    transcode = fn _pcm, opus ->
      send(self(), :transcode_requested)
      File.write!(opus, "OggSfixture")
      :ok
    end

    assert :ok = LiveFixture.ensure!(root: root, request: request, transcode: transcode)
    assert_received :tts_requested
    assert_received :transcode_requested

    assert :ok =
             LiveFixture.ensure!(
               root: root,
               request: fn -> flunk("TTS repeated") end,
               transcode: fn _, _ -> flunk("transcode repeated") end
             )

    assert File.read!(LiveFixture.pcm_path(root)) ==
             <<0, 0, 1, 0, 2, 0, 3, 0>> <> :binary.copy(<<0>>, 64_000)

    assert File.read!(LiveFixture.opus_path(root)) == "OggSfixture"
  end

  test "a failed transcode leaves no newly generated samples" do
    root = Path.join(System.tmp_dir!(), "vxpipe-deepgram-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    assert_raise RuntimeError, "Deepgram fixture transcoding failed", fn ->
      LiveFixture.ensure!(
        root: root,
        request: fn -> {:ok, <<0, 0, 1, 0>>} end,
        transcode: fn _, _ -> {:error, :failed} end
      )
    end

    refute File.exists?(LiveFixture.pcm_path(root))
    refute File.exists?(LiveFixture.opus_path(root))
  end

  test "an existing PCM sample only needs local Opus transcoding" do
    root = Path.join(System.tmp_dir!(), "vxpipe-deepgram-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    pcm = LiveFixture.pcm_path(root)
    File.mkdir_p!(Path.dirname(pcm))
    File.write!(pcm, <<0, 0, 1, 0>>)

    assert :ok =
             LiveFixture.ensure!(
               root: root,
               request: fn -> flunk("TTS repeated") end,
               transcode: fn ^pcm, opus ->
                 File.write!(opus, "OggSfixture")
                 :ok
               end
             )

    assert File.read!(pcm) == <<0, 0, 1, 0>>
    assert File.read!(LiveFixture.opus_path(root)) == "OggSfixture"
  end
end
