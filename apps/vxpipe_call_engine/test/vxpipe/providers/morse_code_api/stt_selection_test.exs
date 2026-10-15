defmodule Vxpipe.Providers.MorseCodeApi.STTSelectionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{
    CapabilityCatalog,
    ModelCatalog,
    SpeechToTextRuntime,
    TestTenantCredentialSource
  }

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.PlanStartup.SpeechProviderResolution
  alias Vxpipe.CallEngine.Speech.ConversationalSTT
  alias Vxpipe.Providers.MorseCodeApi.{CredentialValidation, STTSession}
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

  test "the configured STT provider shares the private origin and uses transcript onset by default" do
    assert {:ok, STTSession} = Registry.fetch_capability("morse_code_api", :stt)

    assert {:ok, [%{id: "morse_stt_v1", name: "MorseCodeApiSTT"}]} =
             ModelCatalog.models("morse_code_api", "speech_to_text")

    assert {:ok, selection} =
             CapabilitySelection.new(
               %{provider: "morse_code_api", model: "morse_stt_v1"},
               :speech_to_text,
               []
             )

    assert selection.vad == false
    assert {:ok, STTSession} = CapabilityCatalog.adapter(selection)

    options = [
      credential_source:
        {TestTenantCredentialSource,
         {self(),
          %{{"tenant", "morse_code_api", "default"} => %{"api_key" => "morse shared key"}}}},
      speech_to_text: [providers: %{STTSession => [enabled: true, media_ingress: []]}]
    ]

    for {origin, socket} <- [
          {"http://127.0.0.1:9876", "ws://127.0.0.1:9876"},
          {"https://morse.example.test", "wss://morse.example.test"}
        ] do
      Application.put_env(:vxpipe_providers, :morse_code_api, base_url: origin, allow_http?: true)

      assert {:ok, {STTSession, config}, settings} =
               SpeechProviderResolution.resolve_provider(
                 selection,
                 "tenant",
                 options,
                 :speech_to_text
               )

      assert config.endpoint == socket
      assert config.api_key == "morse shared key"

      assert {:ok, {STTSession, public}, private} =
               SpeechToTextRuntime.provider({STTSession, config}, settings)

      refute :erlang.term_to_binary(public) =~ socket
      refute inspect(private) =~ "morse shared key"

      assert {:ok, {ConversationalSTT, conversation}, _} =
               SpeechToTextRuntime.conversation(selection, {STTSession, public}, private)

      assert {:ok, descriptor} = ConversationalSTT.configure(conversation)
      assert descriptor.speech_start_evidence == :transcript
      assert descriptor.endpointing == :provider_gap
      assert descriptor.settings.vad == false

      assert {:ok, [name: "morse_code_api", model: "morse_stt_v1"]} =
               SpeechToTextRuntime.usage_identity(STTSession, config)

      assert {:ok, request} =
               CredentialValidation.request("api_key", %{"api_key" => config.api_key})

      assert Keyword.fetch!(request, :url) == origin <> "/v1/models"
    end

    Application.delete_env(:vxpipe_providers, :morse_code_api)

    assert {:error, :unsupported_speech_to_text_configuration} =
             SpeechProviderResolution.resolve_provider(
               selection,
               "tenant",
               options,
               :speech_to_text
             )
  end

  test "public selection rejects routing, authentication and unsupported Morse timing overrides" do
    for options <- [
          %{endpoint: "wss://elsewhere.test"},
          %{api_key: "key"},
          %{wire_module: "other"},
          %{commit_strategy: "manual"},
          %{vad_silence_threshold_secs: 0.42},
          %{sample_rate: 48_000}
        ] do
      assert {:error, _} =
               CapabilitySelection.new(
                 %{provider: "morse_code_api", model: "morse_stt_v1", options: options},
                 :speech_to_text,
                 []
               )
    end
  end
end
