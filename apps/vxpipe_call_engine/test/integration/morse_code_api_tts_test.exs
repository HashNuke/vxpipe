defmodule Vxpipe.CallEngine.Integration.MorseCodeApiTTSTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_morse_code_api
  @moduletag :capture_log
  @moduletag timeout: 60_000

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}
  alias Vxpipe.Providers.MorseCodeApi.{CredentialValidation, TTS, TTSRequest}

  test "the configured API accepts an arbitrary compatibility key and produces independently decoded PCM" do
    key = "vxpipe compatibility smoke key"
    assert {:ok, request} = CredentialValidation.request("api_key", %{"api_key" => key})

    assert {:ok, %{status: 200, body: models}} =
             Req.get(
               Keyword.merge(request, redirect: false, retry: false, receive_timeout: 10_000)
             )

    assert Enum.any?(models, &(&1["model_id"] == "morse_v1"))

    for rate <- [8_000, 16_000, 24_000, 48_000] do
      assert {:ok, config} = TTS.new(api_key: key, sample_rate: rate)
      assert {:ok, local} = Config.new(sample_rate: rate)
      assert {:ok, decoder} = Decoder.new(local)
      state = start_supervised!({Agent, fn -> {decoder, [], 0} end}, id: {Agent, rate})

      assert :ok =
               TTSRequest.run(config, "SOS TEST", fn audio ->
                 Agent.update(state, fn {decoder, events, bytes} ->
                   {:ok, decoder, next} = Decoder.push(decoder, audio)
                   {decoder, events ++ next, bytes + byte_size(audio)}
                 end)
               end)

      {decoder, events, bytes} = Agent.get(state, & &1)
      assert {:ok, _, final} = Decoder.flush(decoder)
      assert for({:final, text} <- events ++ final, do: text) == ["SOS TEST"]
      # SOS (27), word gap (7), TEST (21), final gap (14): 69 units at 60 ms.
      assert bytes == div(rate * 69 * 60 * 2, 1_000)
    end
  end
end
