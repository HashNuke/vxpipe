defmodule Vxpipe.Providers.ElevenLabs.TTSRequestTest do
  use ExUnit.Case, async: true
  @moduletag :integration
  @moduletag :capture_log

  alias Vxpipe.CallEngine.TestTTSHTTPServer
  alias Vxpipe.Providers.ElevenLabs.{TTS, TTSRequest}
  @voice "JBFqnCBsd6RMkjVDRZzb"

  test "streams only aligned PCM from one phrase request" do
    config = config(chunks: [<<1>>, <<0, 2, 0>>])
    observer = self()

    assert :ok =
             TTSRequest.run(config, "Hello", fn pcm ->
               send(observer, {:pcm, pcm})
               :ok
             end)

    assert_receive {:tts_http_request, _, "/tts/bytes/" <> @voice <> "/stream", [], body}
    assert body == %{"text" => "Hello", "model_id" => "eleven_flash_v2_5"}
    chunks = receive_chunks([])
    assert IO.iodata_to_binary(chunks) == <<1, 0, 2, 0>>
    assert Enum.all?(chunks, &(rem(byte_size(&1), 2) == 0))
  end

  for options <- [
        [status: 401],
        [type: "application/json"],
        [chunks: []],
        [chunks: [<<1>>]],
        [status: 302]
      ] do
    test "fails unsuccessful or malformed response #{inspect(options)} without retry" do
      config = config(unquote(Macro.escape(options)))
      observer = self()

      assert {:error, :provider_unavailable} =
               TTSRequest.run(config, "Hello", fn pcm ->
                 send(observer, {:unexpected_pcm, pcm})
                 :ok
               end)

      refute_received {:unexpected_pcm, _pcm}
      assert_receive {:tts_http_request, _, _, _, _}
      refute_receive {:tts_http_request, _, _, _, _}, 50
    end
  end

  test "consumer rejection cannot be reported as successful generation" do
    assert {:error, :provider_unavailable} =
             TTSRequest.run(config([]), "Hello", fn _pcm -> {:error, :closed} end)
  end

  defp config(options) do
    server = start_supervised!({TestTTSHTTPServer, Keyword.put(options, :owner, self())})
    assert {:ok, config} = TTS.new(api_key: "synthetic", voice: @voice)
    %{config | endpoint: TestTTSHTTPServer.endpoint(server)}
  end

  defp receive_chunks(chunks) do
    receive do
      {:pcm, pcm} -> receive_chunks([pcm | chunks])
    after
      0 -> Enum.reverse(chunks)
    end
  end
end
