defmodule Vxpipe.Providers.Cartesia.STTTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Providers.Cartesia.STT
  alias Vxpipe.CallEngine.{CapabilityCatalog, SpeechToTextRuntime}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Providers.Cartesia.STTSession
  alias Vxpipe.Providers.Registry

  test "inline call selection resolves a privately authenticated semantic recognizer" do
    assert {:ok, STTSession} = Registry.fetch_capability("cartesia", :stt)

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "cartesia", model: "ink-2"},
               :speech_to_text,
               ["speech_to_text"]
             )

    assert :ok = CapabilityCatalog.validate(selection)
    assert {:ok, STTSession} = CapabilityCatalog.adapter(selection)
    assert {:ok, public} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = STT.new(Keyword.put(public, :api_key, "synthetic-key"))

    assert {:ok, {STTSession, ^public}, private} =
             SpeechToTextRuntime.provider(
               {STTSession, config},
               enabled: true,
               media_ingress: []
             )

    assert Keyword.fetch!(private, :config) == config
    refute inspect(private) =~ "synthetic-key"

    assert {:ok, [name: "cartesia", model: "ink-2"]} =
             SpeechToTextRuntime.usage_identity(STTSession, config)

    assert {:error, :invalid_configuration} =
             SpeechToTextRuntime.provider({STTSession, config}, transport: __MODULE__)

    for input <- [
          %{model: "ink-1"},
          %{options: %{endpoint: "wss://todo"}},
          %{options: %{api_key: "secret"}}
        ] do
      assert {:error, _reason} =
               CapabilitySelection.new(
                 Map.merge(%{provider: "cartesia", model: "ink-2"}, input),
                 :speech_to_text,
                 ["speech_to_text"]
               )
    end
  end

  test "automatic turns use Ink 2 and privately authenticated 16 kHz PCM" do
    assert {:ok, config} = STT.new(api_key: "synthetic-key")
    refute inspect(config) =~ "synthetic-key"
    connection = STT.connection_options(config)

    assert %URI{scheme: "wss", host: "api.cartesia.ai", path: "/stt/turns/websocket"} =
             URI.parse(connection.url)

    assert URI.decode_query(URI.parse(connection.url).query) == %{
             "model" => "ink-2",
             "encoding" => "pcm_s16le",
             "sample_rate" => "16000"
           }

    assert connection.headers == [
             {"authorization", "Bearer synthetic-key"},
             {"cartesia-version", "2026-08-14"}
           ]

    refute connection.url =~ "synthetic-key"
    assert :ok = STT.validate_audio(<<1, 0, 2, 0>>)

    for audio <- [<<>>, <<1>>, :binary.copy(<<0>>, 32_002), nil] do
      assert {:error, :invalid_audio} = STT.validate_audio(audio)
    end
  end

  test "closed public configuration excludes unsupported formats and private transport hooks" do
    for options <- [
          [model: "ink-1"],
          [encoding: :opus],
          [sample_rate: 48_000],
          [endpoint: "wss://todo"],
          [wire_module: __MODULE__],
          [api_key: "secret"],
          [language: "en"],
          [model: "ink-2", model: "ink-2"]
        ] do
      assert {:error, :invalid_configuration} = STT.public_options(options)
    end

    for key <- [nil, "", "has space", "key\n", :binary.copy("a", 8_193)] do
      assert {:error, :invalid_configuration} = STT.new(api_key: key)
    end
  end

  test "bounded decoder retains cumulative text and connection identity with safe errors" do
    for {type, kind} <- [
          {"connected", :ready},
          {"turn.start", :speech_started},
          {"turn.resume", :turn_resumed}
        ] do
      assert {:ok, {^kind, "connection", nil}} =
               STT.decode(JSON.encode!(%{type: type, request_id: "connection"}))
    end

    for {type, kind} <- [
          {"turn.update", :transcript},
          {"turn.eager_end", :eager_turn_ended},
          {"turn.end", :turn_ended}
        ] do
      assert {:ok, {^kind, "connection", "Hello there."}} =
               STT.decode(
                 JSON.encode!(%{type: type, request_id: "connection", transcript: "Hello there."})
               )

      assert {:error, :invalid_message} =
               STT.decode(JSON.encode!(%{type: type, request_id: "connection"}))
    end

    assert {:error, :provider_failure} = STT.decode(~s({"type":"error","message":"secret"}))

    for payload <- [
          "bad json",
          "[]",
          ~s({"type":"other","request_id":"connection"}),
          ~s({"type":"connected","request_id":""}),
          :binary.copy("x", 262_145),
          JSON.encode!(%{
            type: "turn.end",
            request_id: "c",
            transcript: :binary.copy("x", 65_537)
          })
        ] do
      assert {:error, :invalid_message} = STT.decode(payload)
    end
  end
end
