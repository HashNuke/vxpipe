defmodule Vxpipe.Providers.RegistryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Registry

  test "declares only each provider's supported capabilities" do
    assert {:ok, Vxpipe.Providers.Deepgram} = Registry.fetch("deepgram")
    assert {:ok, Vxpipe.Providers.Deepgram.Credential} =
             Registry.fetch_capability("deepgram", :credential)
    assert {:ok, Vxpipe.Providers.Deepgram.CredentialValidation} =
             Registry.fetch_capability("deepgram", :credential_validation)
    assert {:ok, Vxpipe.Providers.Deepgram.Flux.Session} =
             Registry.fetch_capability("deepgram", :stt)
    assert {:ok, Vxpipe.Providers.Deepgram.FluxTextToSpeech.Session} =
             Registry.fetch_capability("deepgram", :tts)
    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("deepgram", :telephony)
  end

  test "unknown names and capabilities never select a fallback" do
    assert {:error, :unsupported_provider} = Registry.fetch("unknown")
    assert {:error, :unsupported_provider} = Registry.fetch_capability("unknown", :stt)
    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("deepgram", :unknown)
  end

  test "resolution checks installed implementations independently of declared support" do
    assert {:ok, Vxpipe.Providers.Deepgram.Credential} =
             Registry.resolve_capability("deepgram", :credential)

    assert {:error, :unsupported_provider_capability} =
             Registry.resolve_capability("deepgram", :telephony)

    assert {:error, :unsupported_provider} = Registry.resolve_capability("unknown", :stt)
  end

  test "catalog contains explicit capability metadata" do
    assert Registry.catalog() == %{
             "deepgram" => [:credential, :credential_validation, :stt, :tts]
           }
  end
end
