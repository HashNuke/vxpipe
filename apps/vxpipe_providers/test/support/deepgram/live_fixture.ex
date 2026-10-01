defmodule Vxpipe.Providers.Deepgram.LiveFixture do
  @moduledoc false

  @text "The final word is telescope."
  @fixture_model Vxpipe.Providers.LiveModels.speech("deepgram", :fixture_tts)
  @tts_url "https://api.deepgram.com/v1/speak?model=#{@fixture_model}&encoding=linear16&container=none&sample_rate=16000"
  @root Path.expand("../../../../..", __DIR__)
  @trailing_silence_bytes 64_000

  def pcm_path(root \\ @root) do
    Path.join(
      root,
      "apps/vxpipe_providers/test/fixtures/deepgram/final_word_16k_mono_s16le.pcm"
    )
  end

  def opus_path(root \\ @root) do
    Path.join(root, "apps/vxpipe_providers/test/fixtures/deepgram/final_word_48k_mono_opus.ogg")
  end

  def short_pcm_path(root \\ @root) do
    Path.join(root, "apps/vxpipe_providers/test/fixtures/deepgram/short_answer_16k_mono_s16le.pcm")
  end

  def ensure_short!(options \\ []) do
    path = short_pcm_path(Keyword.get(options, :root, @root))

    unless File.regular?(path) do
      request = Keyword.get(options, :request, fn -> request_tts!("Yes.") end)

      case request.() do
        {:ok, audio}
        when is_binary(audio) and byte_size(audio) in 2..64_000 and rem(byte_size(audio), 2) == 0 ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, audio)

        _failure ->
          raise "Deepgram short fixture must be nonempty 16 kHz PCM of at most two seconds"
      end
    end

    :ok
  end

  def ensure!(options \\ []) do
    root = Keyword.get(options, :root, @root)
    pcm = pcm_path(root)
    opus = opus_path(root)

    if File.regular?(pcm) and File.regular?(opus) do
      :ok
    else
      scratch =
        Path.join(System.tmp_dir!(), "vxpipe-deepgram-#{System.unique_integer([:positive])}")

      File.mkdir_p!(scratch)

      try do
        generate_missing!(
          pcm,
          opus,
          scratch,
          Keyword.get(options, :request, &request_tts!/0),
          Keyword.get(options, :transcode, &transcode/2)
        )
      after
        File.rm_rf!(scratch)
      end
    end
  end

  defp generate_missing!(pcm, opus, scratch, request, transcode) do
    scratch_pcm = Path.join(scratch, "speech.pcm")
    scratch_opus = Path.join(scratch, "speech.ogg")

    pcm_input =
      if File.regular?(pcm) do
        pcm
      else
        case request.() do
          {:ok, audio} when is_binary(audio) ->
            File.write!(scratch_pcm, streaming_sample!(audio))

          _ ->
            raise "Deepgram fixture TTS request failed"
        end

        scratch_pcm
      end

    bytes = File.stat!(pcm_input).size

    unless bytes >= 2 and bytes <= 320_000 and rem(bytes, 2) == 0 do
      raise "Deepgram fixture must be nonempty 16 kHz PCM of at most 10 seconds"
    end

    unless File.regular?(opus) do
      unless transcode.(pcm_input, scratch_opus) == :ok and
               File.regular?(scratch_opus) and
               match?(<<"OggS", _::binary>>, File.read!(scratch_opus)) do
        raise "Deepgram fixture transcoding failed"
      end
    end

    unless File.regular?(pcm) do
      File.mkdir_p!(Path.dirname(pcm))
      File.rename!(scratch_pcm, pcm)
    end

    unless File.regular?(opus) do
      File.mkdir_p!(Path.dirname(opus))
      File.rename!(scratch_opus, opus)
    end

    :ok
  end

  defp streaming_sample!(audio) do
    unless byte_size(audio) in 2..(320_000 - @trailing_silence_bytes) and
             rem(byte_size(audio), 2) == 0 do
      raise "Deepgram fixture must be nonempty 16 kHz PCM of at most 10 seconds"
    end

    audio <> :binary.copy(<<0>>, @trailing_silence_bytes)
  end

  defp request_tts!(text \\ @text) do
    key = System.fetch_env!("DEEPGRAM_API_KEY")

    case Req.post(@tts_url,
           headers: [{"authorization", "Token " <> key}],
           json: %{text: text},
           retry: false,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: audio}} when is_binary(audio) -> {:ok, audio}
      _ -> raise "Deepgram fixture TTS request failed"
    end
  end

  defp transcode(pcm, opus) do
    args = [
      "-nostdin",
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "s16le",
      "-ar",
      "16000",
      "-ac",
      "1",
      "-i",
      pcm,
      "-ar",
      "48000",
      "-ac",
      "1",
      "-c:a",
      "libopus",
      "-application",
      "voip",
      "-b:a",
      "32000",
      "-f",
      "ogg",
      opus
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, :failed}
    end
  rescue
    ErlangError -> {:error, :failed}
  end
end
