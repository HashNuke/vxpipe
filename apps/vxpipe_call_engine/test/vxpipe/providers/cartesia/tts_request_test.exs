defmodule Vxpipe.Providers.Cartesia.TTSRequestTest do
  use ExUnit.Case, async: true
  @moduletag :integration
  @moduletag :capture_log
  alias Vxpipe.CallEngine.TestTTSHTTPServer
  alias Vxpipe.Providers.Cartesia.{TTS, TTSRequest}

  test "sends one versioned request and exposes only aligned PCM chunks" do
    config = config(chunks: [<<1>>, <<0, 2, 0>>])
    owner = self()

    assert :ok =
             TTSRequest.run(config, "Hello", fn pcm ->
               send(owner, {:pcm, pcm})
               :ok
             end)

    assert_receive {:tts_http_request, _, "/tts/bytes", ["Bearer synthetic"], body}
    assert body["voice"] == config.voice

    assert body["output_format"] == %{
             "container" => "raw",
             "encoding" => "pcm_s16le",
             "sample_rate" => 24_000
           }

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
    test "rejects unsuccessful or malformed response #{inspect(options)}" do
      config = config(unquote(Macro.escape(options)))

      assert {:error, :provider_unavailable} =
               TTSRequest.run(config, "Hello", fn _ -> flunk("invalid response exposed audio") end)

      assert_receive {:tts_http_request, _, "/tts/bytes", _, _}
      refute_receive {:tts_http_request, _, _, _, _}, 50
    end
  end

  test "consumer failure terminates this request without returning successful completion" do
    assert {:error, :provider_unavailable} =
             TTSRequest.run(config([]), "Hello", fn _ -> {:error, :closed} end)
  end

  defp config(options) do
    server = start_supervised!({TestTTSHTTPServer, Keyword.put(options, :owner, self())})
    {:ok, config} = TTS.new(api_key: "synthetic", voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4")
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
