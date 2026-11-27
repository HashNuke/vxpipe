defmodule Vxpipe.Providers.ElevenLabs.ScribeQueryLanguagesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.CallEngine.SpeechToTextRuntime
  alias Vxpipe.Providers.ElevenLabs.Scribe
  alias Vxpipe.Providers.ElevenLabs.STTSession, as: ScribeSession

  @models ["scribe_v2_realtime", "scribe_v3_live"]

  for model <- @models do
    @model model
    test "actual #{@model} websocket query carries primary plus repeated secondary languages" do
      input = %{provider: "elevenlabs", model: @model, languages: ["en", "es", "fr"]}

      assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_text, [])
      assert {:ok, options} = CapabilityCatalog.speech_options(selection)
      assert Keyword.get(options, :language_code) == "en"
      assert Keyword.get(options, :secondary_languages) == ["es", "fr"]

      assert {:ok, config} =
               Scribe.new(Keyword.put(options, :api_key, "synthetic"))

      assert config.language_code == "en"
      assert config.secondary_languages == ["es", "fr"]

      pairs =
        config
        |> Scribe.connection_options()
        |> Map.fetch!(:url)
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.query_decoder()
        |> Enum.to_list()

      assert {"language_code", "en"} in pairs
      assert for({"secondary_languages", code} <- pairs, do: code) == ["es", "fr"]
      assert {"model_id", @model} in pairs

      # Provider-configured selection preserves the same language wiring.
      assert {:ok, {ScribeSession, public}, private} =
               SpeechToTextRuntime.provider({ScribeSession, config}, [])

      assert Keyword.get(public, :language_code) == "en"
      assert Keyword.get(public, :secondary_languages) == ["es", "fr"]
      assert Keyword.fetch!(private, :config) == config

      assert {:ok, reconfigured} =
               Scribe.new(Keyword.put(public, :api_key, "synthetic"))

      assert Scribe.connection_options(reconfigured).url ==
               Scribe.connection_options(config).url
    end
  end

  test "single primary language omits repeated secondary params" do
    input = %{provider: "elevenlabs", model: "scribe_v2_realtime", languages: ["es"]}

    assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_text, [])
    assert {:ok, options} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = Scribe.new(Keyword.put(options, :api_key, "synthetic"))

    pairs =
      config
      |> Scribe.connection_options()
      |> Map.fetch!(:url)
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.query_decoder()
      |> Enum.to_list()

    assert {"language_code", "es"} in pairs
    assert for({"secondary_languages", code} <- pairs, do: code) == []
  end
end
