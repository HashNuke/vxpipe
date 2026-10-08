defmodule Vxpipe.CallEngine.ModelCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.ModelCatalog

  @providers %{
    "speech_to_text" => ~w(cartesia deepgram elevenlabs google morse),
    "output_speech_to_text" => ~w(cartesia deepgram elevenlabs google morse),
    "text_to_speech" => ~w(cartesia deepgram elevenlabs google morse rime),
    "speech_to_speech" => ~w(google morse openai),
    "model_inference" => ~w(deepseek fireworks google openai openrouter zenmux)
  }

  for {capability, providers} <- @providers do
    test "#{capability} offers installed providers and their declared models" do
      assert {:ok, providers} = ModelCatalog.providers(unquote(capability))
      assert Enum.map(providers, & &1.id) == unquote(providers)

      for provider <- providers do
        assert is_binary(provider.name) and provider.name != ""
        assert {:ok, models} = ModelCatalog.models(provider.id, unquote(capability))
        assert models != []
        assert Enum.count(models, & &1.default) == 1
      end
    end
  end

  test "the combined catalog uses the same installed model declarations" do
    catalog = ModelCatalog.catalog()
    assert [%{id: "flux"}] = catalog["text_to_speech"]["deepgram"]
    assert Enum.find(catalog["model_inference"]["google"], & &1.default).id == "gemini-2.5-flash"
    refute Map.has_key?(catalog["speech_to_speech"], "deepgram")
  end

  test "model descriptors retain adapter-owned voices and LLM limits" do
    assert {:ok, [%{id: "flux", voices: %{default: "hannah", parameter: "voice"}}]} =
             ModelCatalog.models("deepgram", "text_to_speech")

    assert {:ok, models} = ModelCatalog.models("deepseek", "model_inference")
    assert %{context_limit: 1_048_576} = Enum.find(models, & &1.default)
  end

  test "unknown providers, unsupported pairs and invalid capabilities are distinct" do
    assert {:error, :unsupported_provider} = ModelCatalog.models("unknown", "speech_to_text")

    assert {:error, :unsupported_provider_capability} =
             ModelCatalog.models("deepgram", "model_inference")

    for capability <- [nil, "unknown", "stt", :speech_to_text] do
      assert {:error, :invalid_capability} = ModelCatalog.providers(capability)
      assert {:error, :invalid_capability} = ModelCatalog.models("google", capability)
    end
  end

  test "a host without implementation applications does not advertise unavailable providers" do
    source = Path.expand("../../../lib/vxpipe/call_engine/model_catalog.ex", __DIR__)
    providers_path = Application.app_dir(:vxpipe_providers, "ebin")

    script = """
    Code.compiler_options(no_warn_undefined: :all)
    Code.require_file(#{inspect(source)})
    for capability <- #{inspect(Map.keys(@providers))} do
      {:ok, []} = Vxpipe.CallEngine.ModelCatalog.providers(capability)
    end
    IO.puts("unavailable providers omitted")
    """

    assert {output, 0} =
             System.cmd("elixir", ["-pa", providers_path, "-e", script], stderr_to_stdout: true)

    assert output =~ "unavailable providers omitted"
  end
end
