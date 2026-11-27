defmodule Vxpipe.Providers.Deepgram.FluxLanguagesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.Providers.Deepgram.{Flux, STTSession}

  test "Flux resolves the selected languages and preserves repeated hints on its socket" do
    for {model, languages, wire_model, hints} <- [
          {"flux", [], "flux-general-multi", []},
          {"flux", ["en"], "flux-general-en", []},
          {"flux", ["es"], "flux-general-multi", ["es"]},
          {"flux", ["en", "es"], "flux-general-multi", ["en", "es"]},
          {"flux-general-multi", ["en"], "flux-general-multi", ["en"]}
        ] do
      input = %{
        provider: "deepgram",
        model: model,
        languages: languages,
        options: %{encoding: "linear16", sample_rate: 16_000}
      }

      assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_text, [])
      assert {:ok, options} = CapabilityCatalog.speech_options(selection)
      assert {:ok, _descriptor} = STTSession.configure(options)
      assert {:ok, config} = Flux.new(Keyword.put(options, :api_key, "test"))

      pairs =
        Flux.connection_options(config).url
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.query_decoder()
        |> Enum.to_list()

      assert {"model", wire_model} in pairs
      assert for({"language_hint", code} <- pairs, do: code) == hints
    end
  end
end
