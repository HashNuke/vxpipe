defmodule Vxpipe.Providers.MorseCodeApi.TTSRequestTest do
  use ExUnit.Case, async: true
  @moduletag :integration
  @moduletag :capture_log

  alias Vxpipe.CallEngine.TestTTSHTTPServer
  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, TTS, TTSRequest}

  test "uses the selected local origin and streams only complete PCM samples" do
    config = config(chunks: [<<1>>, <<0, 2, 0>>])
    owner = self()

    assert :ok =
             TTSRequest.run(config, "SOS", fn pcm ->
               send(owner, {:pcm, pcm})
               :ok
             end)

    assert_receive {:tts_http_request, _, "/v1/text-to-speech/morse/stream", [], body}
    assert body == %{"model_id" => "morse_v1", "text" => "SOS"}
    assert IO.iodata_to_binary(chunks([])) == <<1, 0, 2, 0>>
  end

  for options <- [
        [status: 401],
        [type: "application/json"],
        [chunks: []],
        [chunks: [<<1>>]],
        [status: 302]
      ] do
    test "fails #{inspect(options)} without retry or redirect" do
      config = config(unquote(Macro.escape(options)))

      assert {:error, :provider_unavailable} =
               TTSRequest.run(config, "E", fn _ -> flunk("unexpected audio") end)

      assert_receive {:tts_http_request, _, _, _, _}
      refute_receive {:tts_http_request, _, _, _, _}, 50
    end
  end

  test "consumer rejection prevents successful completion" do
    assert {:error, :provider_unavailable} =
             TTSRequest.run(config([]), "E", fn _ -> {:error, :closed} end)
  end

  defp config(options) do
    server = start_supervised!({TestTTSHTTPServer, Keyword.put(options, :owner, self())})

    origin =
      server
      |> TestTTSHTTPServer.endpoint()
      |> URI.new!()
      |> Map.put(:path, nil)
      |> URI.to_string()

    assert {:ok, endpoint} = Endpoint.new(origin, allow_http?: true)
    assert {:ok, config} = TTS.new([api_key: "synthetic"], endpoint)
    config
  end

  defp chunks(acc) do
    receive do
      {:pcm, pcm} ->
        assert rem(byte_size(pcm), 2) == 0
        chunks([pcm | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
