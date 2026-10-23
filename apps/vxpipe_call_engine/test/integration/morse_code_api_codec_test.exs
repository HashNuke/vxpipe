defmodule Vxpipe.CallEngine.Integration.MorseCodeApiCodecTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}

  @moduletag :integration
  @moduletag :live_morse_code_api
  @moduletag timeout: 60_000
  @phrase "SOS TEST 123"

  setup do
    origin = System.fetch_env!("MORSE_CODE_API_BASE_URL") |> String.trim_trailing("/")
    {:ok, origin: origin}
  end

  test "Go PCM synthesis decodes with the existing Elixir codec at every shared rate", %{
    origin: origin
  } do
    for rate <- [8_000, 16_000, 24_000, 48_000] do
      assert {:ok, %Req.Response{status: 200, body: pcm}} =
               Req.post(origin <> "/v1/text-to-speech/morse",
                 headers: [{"xi-api-key", "synthetic-codec-interop"}],
                 params: [output_format: "pcm_#{rate}"],
                 json: %{text: @phrase, model_id: "morse_v1"},
                 decode_body: false,
                 retry: false,
                 redirect: false,
                 receive_timeout: 10_000
               )

      assert {:ok, config} = Config.new(sample_rate: rate)
      assert {:ok, decoder} = Decoder.new(config)

      {decoder, events} =
        pcm
        |> chunks()
        |> Enum.reduce({decoder, []}, fn chunk, {decoder, events} ->
          assert {:ok, next, emitted} = Decoder.push(decoder, chunk)
          {next, events ++ emitted}
        end)

      assert {:ok, _decoder, tail} = Decoder.flush(decoder)
      assert Enum.filter(events ++ tail, &match?({:final, _}, &1)) == [{:final, @phrase}]
    end
  end

  test "Elixir synthesis transcribes through Go multipart PCM recognition", %{origin: origin} do
    assert {:ok, config} = Config.new()
    assert {:ok, pcm} = Encoder.encode(config, @phrase)

    assert {:ok, %Req.Response{status: 200, body: result}} =
             Req.post(origin <> "/v1/speech-to-text",
               headers: [{"xi-api-key", "a-different-synthetic-key"}],
               form_multipart: [
                 file: {pcm, filename: "morse.pcm", content_type: "application/octet-stream"},
                 model_id: "scribe_v2",
                 file_format: "pcm_s16le_16"
               ],
               retry: false,
               redirect: false,
               receive_timeout: 10_000
             )

    assert result["text"] == @phrase
    assert Enum.map(result["words"], & &1["text"]) == ["SOS", " ", "TEST", " ", "123"]
  end

  defp chunks(pcm) do
    Stream.unfold(pcm, fn
      <<>> ->
        nil

      remaining ->
        count = min(byte_size(remaining), 317)
        <<chunk::binary-size(count), tail::binary>> = remaining
        {chunk, tail}
    end)
  end
end
