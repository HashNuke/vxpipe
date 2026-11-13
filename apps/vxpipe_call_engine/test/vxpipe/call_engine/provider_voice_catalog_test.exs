defmodule Vxpipe.CallEngine.ProviderVoiceCatalogTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.{ModelCatalog, VoiceCatalog}
  alias Vxpipe.Providers.{Cartesia, Deepgram, ElevenLabs, Google, OpenAI, Rime}
  @id "00000000-0000-4000-8000-000000000001"
  @payload %{"api_key" => "synthetic-account-key"}
  @plug [plug: {Req.Test, __MODULE__}]

  test "Cartesia forwards account-scoped search filters and cursor; drops archived or invalid wire IDs" do
    scope = scope("cartesia", "sonic-3.6")

    voice = %{
      "id" => @id,
      "name" => "Reception",
      "status" => "active",
      "language" => "en",
      "gender" => "feminine"
    }

    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer synthetic-account-key"]

      assert Plug.Conn.get_req_header(conn, "cartesia-version") == [
               Cartesia.TTS.cartesia_version()
             ]

      case conn.request_path do
        "/voices" ->
          assert conn.params == %{
                   "q" => "reception",
                   "limit" => "50",
                   "starting_after" => @id,
                   "language" => "en",
                   "is_owner" => "true"
                 }

          Req.Test.json(conn, %{
            "data" => [voice, %{voice | "status" => "archived"}],
            "has_more" => true,
            "next_page" => @id
          })

        "/voices/" <> @id ->
          Req.Test.json(conn, voice)
      end
    end)

    assert {:ok, %{voices: [entry], nextCursor: @id}} =
             VoiceCatalog.list(
               scope,
               %{
                 "search" => "reception",
                 "filters" => %{"language" => "en", "is_owner" => true},
                 "cursor" => @id
               },
               @payload,
               @plug
             )

    assert entry.id == @id
    assert {:ok, ^entry} = VoiceCatalog.get(scope, @id, @payload, @plug)
    assert {:ok, %{voice: @id}} = Cartesia.TTS.public_options(model: scope.model, voice: entry.id)

    Req.Test.stub(
      __MODULE__,
      &Req.Test.json(&1, %{"data" => [%{voice | "id" => "not-a-uuid"}], "has_more" => false})
    )

    assert {:error, :invalid_voice_catalog_response} =
             VoiceCatalog.list(scope, %{}, @payload, @plug)
  end

  test "Rime uses public metadata and limits speakers to the installed model and default language" do
    voices =
      for n <- 1..65,
          do: %{
            "speaker" => "speaker#{n}",
            "modelId" => "coda",
            "lang" => "eng",
            "gender" => "Female",
            "country" => "US"
          }

    other = [
      %{"speaker" => "spanish", "modelId" => "coda", "lang" => "spa"},
      %{"speaker" => "other-model", "modelId" => "mistv3", "lang" => "eng"}
    ]

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "users.rime.ai"
      assert conn.request_path == "/data/voices/voice_details.json"
      assert Plug.Conn.get_req_header(conn, "authorization") == []
      Req.Test.json(conn, voices ++ other)
    end)

    scope = scope("rime", "coda")

    assert {:ok, %{voices: page, total: 65, nextCursor: "50"}} =
             VoiceCatalog.list(scope, %{}, @payload, @plug)

    assert length(page) == 50

    assert {:ok, %{voices: tail, nextCursor: nil}} =
             VoiceCatalog.list(scope, %{"cursor" => "50"}, @payload, @plug)

    assert length(tail) == 15
    assert {:ok, %{id: "speaker65"}} = VoiceCatalog.get(scope, "speaker65", @payload, @plug)
    assert {:ok, nil} = VoiceCatalog.get(scope, "spanish", @payload, @plug)

    assert {:ok, %{voices: [%{id: "speaker65"}]}} =
             VoiceCatalog.list(
               scope,
               %{"search" => "speaker65", "filters" => %{"gender" => "Female"}},
               @payload,
               @plug
             )

    for entry <- page ++ tail,
        do: assert({:ok, _} = Rime.TTS.public_options(model: "coda", speaker: entry.id))
  end

  test "named Google, OpenAI and Flux choices pass existing option parsers without HTTP" do
    Req.Test.stub(__MODULE__, fn _ -> flunk("Named catalogs must not fetch or synthesize") end)

    cases = [
      {scope("google", "gemini-3.1-flash-tts-preview"), Google.TTS, "Kore", 30},
      {scope("google", "gemini-3.8-live", "speech_to_speech"), Google.STS, "Kore", 30},
      {scope("openai", "gpt-live-1", "speech_to_speech"), OpenAI.GPTLive, "marin", 38},
      {scope("deepgram", "flux"), Deepgram.FluxTextToSpeech, "hannah", 36}
    ]

    for {scope, adapter, default, count} <- cases do
      assert {:ok, %{voices: voices, total: ^count, nextCursor: nil}} =
               VoiceCatalog.list(scope, %{}, @payload, @plug)

      assert Enum.any?(voices, &(&1.id == default))

      for voice <- voices do
        assert {:ok, _} = adapter.public_options(model: scope.model, voice: voice.id)
        assert_wire_voice(adapter, scope.model, voice.id)
      end

      assert {:ok, %{id: ^default}} = VoiceCatalog.get(scope, default, @payload, @plug)
      assert {:ok, nil} = VoiceCatalog.get(scope, "voice-custom-unsupported", @payload, @plug)
    end

    assert {:ok, %{voices: [%{id: "haley"}]}} =
             VoiceCatalog.list(scope("deepgram", "flux"), %{"search" => "haley"}, @payload, @plug)

    assert {:ok, "flux-haley-en"} = Deepgram.FluxTextToSpeech.model_for_voice("haley")
  end

  test "ElevenLabs Realtime keeps catalog IDs unchanged in the output voice string for Mini and Max" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "xi-api-key") == ["synthetic-account-key"]

      voice = %{
        "voice_id" => "privateVoice123",
        "name" => "Private voice",
        "category" => "cloned"
      }

      if conn.request_path == "/v2/voices",
        do: Req.Test.json(conn, %{"voices" => [voice], "has_more" => false}),
        else: Req.Test.json(conn, voice)
    end)

    for model <- ["eleven_realtime_v1_mini", "eleven_realtime_v1_max"] do
      scope = scope("elevenlabs", model, "speech_to_speech")
      assert {:ok, %{voices: voices}} = VoiceCatalog.list(scope, %{}, @payload, @plug)
      assert Enum.any?(voices, &(&1.id == "privateVoice123"))

      assert {:ok, %{id: "privateVoice123"}} =
               VoiceCatalog.get(scope, "privateVoice123", @payload, @plug)

      assert {:ok, config} =
               ElevenLabs.Realtime.new(
                 model: model,
                 voice: "privateVoice123",
                 api_key: "synthetic-account-key"
               )

      assert get_in(ElevenLabs.Realtime.session(config), ["audio", "output", "voice"]) ==
               "privateVoice123"

      assert {:ok, %{id: "brian"}} = VoiceCatalog.get(scope, "brian", @payload, @plug)
    end
  end

  test "public and private adapters reject malformed pages and preserve sanitized failures" do
    for scope <- [scope("cartesia", "sonic-3.6"), scope("rime", "coda")] do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, %{"private" => "must never be returned"}))

      assert {:error, :invalid_voice_catalog_response} =
               VoiceCatalog.list(scope, %{}, @payload, @plug)

      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 429, "private upstream response"))

      assert {:error, :voice_catalog_rate_limited} =
               VoiceCatalog.list(scope, %{}, @payload, @plug)
    end
  end

  test "every installed voice-bearing model has an authoring catalog" do
    for capability <- ["text_to_speech", "speech_to_speech"] do
      {:ok, providers} = ModelCatalog.providers(capability)

      for provider <- providers do
        {:ok, models} = ModelCatalog.models(provider.id, capability)

        for model <- models, model.voices != nil do
          assert {:ok, _} = VoiceCatalog.describe(scope(provider.id, model.id, capability))
        end
      end
    end
  end

  test "malformed public rows fail visibly and optional private names fall back to IDs" do
    Req.Test.stub(__MODULE__, &Req.Test.json(&1, [%{}]))

    assert {:error, :invalid_voice_catalog_response} =
             VoiceCatalog.list(scope("rime", "coda"), %{}, @payload, @plug)

    Req.Test.stub(
      __MODULE__,
      &Req.Test.json(&1, %{
        "voices" => [%{"voice_id" => "unnamedVoice", "name" => nil}],
        "has_more" => false
      })
    )

    assert {:ok, %{voices: [%{id: "unnamedVoice", name: "unnamedVoice"}]}} =
             VoiceCatalog.list(scope("elevenlabs", "eleven_flash_v2_5"), %{}, @payload, @plug)
  end

  defp assert_wire_voice(Google.TTS, model, id) do
    assert {:ok, config} = Google.TTS.new(model: model, voice: id, api_key: "synthetic-key")

    assert Google.TTS.request_body(config, "Fixture").generation_config.speech_config == [
             %{voice: id}
           ]
  end

  defp assert_wire_voice(Google.STS, model, id) do
    assert {:ok, config} = Google.STS.new(model: model, voice: id, api_key: "synthetic-key")

    assert get_in(Google.STS.setup(config), [
             "setup",
             "generationConfig",
             "speechConfig",
             "voiceConfig",
             "prebuiltVoiceConfig",
             "voiceName"
           ]) == id
  end

  defp assert_wire_voice(OpenAI.GPTLive, model, id) do
    assert {:ok, config} = OpenAI.GPTLive.new(model: model, voice: id, api_key: "synthetic-key")
    assert get_in(OpenAI.GPTLive.start(config, []), ["session", "audio", "output", "voice"]) == id
  end

  defp assert_wire_voice(Deepgram.FluxTextToSpeech, _, id) do
    assert {:ok, wire} = Deepgram.FluxTextToSpeech.model_for_voice(id)
    assert wire == "flux-#{id}-en"
  end

  defp scope(provider, model, capability \\ "text_to_speech"),
    do: %{provider: provider, model: model, capability: capability}
end
