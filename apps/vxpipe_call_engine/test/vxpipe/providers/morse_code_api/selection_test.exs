defmodule Vxpipe.Providers.MorseCodeApi.SelectionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{CapabilityCatalog, ModelCatalog, TestTenantCredentialSource}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.PlanStartup.SpeechProviderResolution
  alias Vxpipe.Providers.MorseCodeApi.{CredentialValidation, TTSSession}
  alias Vxpipe.Providers.Registry

  setup do
    previous = Application.fetch_env(:vxpipe_providers, :morse_code_api)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:vxpipe_providers, :morse_code_api, value)
        :error -> Application.delete_env(:vxpipe_providers, :morse_code_api)
      end
    end)
  end

  test "portable TTS selection resolves credentials and probes at the current private origin" do
    Application.delete_env(:vxpipe_providers, :morse_code_api)

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "morse_code_api", model: "morse_v1"},
               :text_to_speech,
               []
             )

    assert {:ok, TTSSession} = CapabilityCatalog.adapter(selection)

    assert {:ok, [%{name: "MorseCodeApiTTS"}]} =
             ModelCatalog.models("morse_code_api", "text_to_speech")

    assert {:ok, Vxpipe.Providers.MorseCodeApi.STTSession} =
             Registry.fetch_capability("morse_code_api", :stt)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("morse_code_api", :sts)

    options = [
      credential_source:
        {TestTenantCredentialSource,
         {self(),
          %{{"tenant", "morse_code_api", "default"} => %{"api_key" => "my compatibility key"}}}},
      text_to_speech: [providers: %{TTSSession => [enabled: true, maximum_requests: 4]}]
    ]

    assert {:error, :unsupported_text_to_speech_configuration} =
             SpeechProviderResolution.resolve_provider(
               selection,
               "tenant",
               options,
               :text_to_speech
             )

    assert {:error, :provider_validation_unavailable} =
             CredentialValidation.request("api_key", %{"api_key" => "my compatibility key"})

    for origin <- ["http://127.0.0.1:9876", "https://hosted.morse.example"] do
      Application.put_env(:vxpipe_providers, :morse_code_api, base_url: origin, allow_http?: true)

      assert {:ok, {TTSSession, config}, settings} =
               SpeechProviderResolution.resolve_provider(
                 selection,
                 "tenant",
                 options,
                 :text_to_speech
               )

      assert config.endpoint == origin
      assert config.api_key == "my compatibility key"
      assert Keyword.fetch!(settings, :credential_identity)["id"] == "morse_code_api-credential"

      assert {:ok, probe} =
               CredentialValidation.request("api_key", %{"api_key" => "my compatibility key"})

      assert Keyword.fetch!(probe, :url) == origin <> "/v1/models"
      assert {"xi-api-key", "my compatibility key"} in Keyword.fetch!(probe, :headers)
      refute :erlang.term_to_binary(selection) =~ origin
    end
  end

  test "public options cannot redirect a selected provider or insert keys" do
    for option <- ["endpoint", "base_url", "api_key", "request_module"] do
      assert {:error, _} =
               CapabilitySelection.new(
                 %{
                   provider: "morse_code_api",
                   model: "morse_v1",
                   options: %{option => "https://other.example"}
                 },
                 :text_to_speech,
                 []
               )
    end
  end
end
