defmodule Vxpipe.Providers.Deepgram.FluxQueryHintsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.CallEngine.SpeechToTextRuntime
  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession

  defp pairs(config) do
    config
    |> Flux.connection_options()
    |> Map.fetch!(:url)
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.query_decoder()
    |> Enum.to_list()
  end

  defp select!(model, languages) do
    input = %{
      provider: "deepgram",
      model: model,
      languages: languages,
      options: %{encoding: "linear16", sample_rate: 16_000}
    }

    assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_text, [])
    assert {:ok, options} = CapabilityCatalog.speech_options(selection)
    assert {:ok, _descriptor} = FluxSession.configure(options)
    assert {:ok, config} = Flux.new(Keyword.put(options, :api_key, "synthetic"))
    {options, config}
  end

  test "explicit English resolves to flux-general-en with no language_hint" do
    for model <- ["flux", "flux-general-en"] do
      {_options, config} = select!(model, ["en"])
      assert config.model == "flux-general-en"
      assert config.language_hints == []
      query = pairs(config)
      assert {"model", "flux-general-en"} in query
      assert for({"language_hint", code} <- query, do: code) == []

      assert {:ok, {FluxSession, public}, private} =
               SpeechToTextRuntime.provider({FluxSession, config}, [])

      assert Keyword.get(public, :model) == "flux-general-en"
      refute Keyword.has_key?(public, :language_hints)
      assert Keyword.fetch!(private, :config) == config
    end
  end

  test "multi with regional hints preserves repeated language_hint params" do
    {_options, config} = select!("flux", ["en-US", "es-ES"])
    assert config.model == "flux-general-multi"
    assert config.language_hints == ["en-US", "es-ES"]

    query = pairs(config)
    assert {"model", "flux-general-multi"} in query
    assert for({"language_hint", code} <- query, do: code) == ["en-US", "es-ES"]

    assert {:ok, {FluxSession, public}, private} =
             SpeechToTextRuntime.provider({FluxSession, config}, [])

    assert Keyword.get(public, :model) == "flux-general-multi"
    assert Keyword.get(public, :language_hints) == ["en-US", "es-ES"]
    assert Keyword.fetch!(private, :config) == config
  end

  test "explicit multi model keeps a single regional hint" do
    {_options, config} = select!("flux-general-multi", ["en-US"])
    assert config.model == "flux-general-multi"
    assert config.language_hints == ["en-US"]
    assert for({"language_hint", code} <- pairs(config), do: code) == ["en-US"]
  end
end
