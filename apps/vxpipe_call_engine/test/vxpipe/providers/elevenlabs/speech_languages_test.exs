defmodule Vxpipe.Providers.ElevenLabs.SpeechLanguagesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.Providers.ElevenLabs.Scribe

  test "a standard language selection reaches the Scribe socket" do
    input = %{provider: "elevenlabs", model: "scribe_v2_realtime", languages: ["es"]}
    assert {:ok, selection} = CapabilitySelection.new(input, :speech_to_text, [])
    assert {:ok, options} = CapabilityCatalog.speech_options(selection)
    assert {:ok, config} = Scribe.new(Keyword.put(options, :api_key, "test"))

    query =
      config
      |> Scribe.connection_options()
      |> Map.fetch!(:url)
      |> URI.parse()
      |> Map.fetch!(:query)

    assert URI.decode_query(query)["language_code"] == "es"
  end
end
