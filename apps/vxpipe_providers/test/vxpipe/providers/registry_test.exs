defmodule Vxpipe.Providers.RegistryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Registry

  test "declares only each provider's supported capabilities" do
    assert {:ok, Vxpipe.Providers.Deepgram} = Registry.fetch("deepgram")

    assert {:ok, Vxpipe.Providers.Deepgram.Credential} =
             Registry.fetch_capability("deepgram", :credential)

    assert {:ok, Vxpipe.Providers.Deepgram.CredentialValidation} =
             Registry.fetch_capability("deepgram", :credential_validation)

    assert {:ok, Vxpipe.Providers.Deepgram.STTSession} =
             Registry.fetch_capability("deepgram", :stt)

    assert {:ok, Vxpipe.Providers.Deepgram.TTSSession} =
             Registry.fetch_capability("deepgram", :tts)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("deepgram", :telephony)

    assert {:ok, Vxpipe.Providers.Telnyx} = Registry.fetch("telnyx")

    assert {:ok, Vxpipe.Providers.Telnyx.Credential} =
             Registry.fetch_capability("telnyx", :credential)

    assert {:ok, Vxpipe.Providers.Telnyx.CredentialValidation} =
             Registry.fetch_capability("telnyx", :credential_validation)

    assert {:ok, Vxpipe.Providers.Telnyx.ServiceProfile} =
             Registry.fetch_capability("telnyx", :telephony)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("telnyx", :stt)

    assert {:ok, Vxpipe.Providers.Google} = Registry.fetch("google")

    assert {:ok, Vxpipe.Providers.Google.Credential} =
             Registry.fetch_capability("google", :credential)

    assert {:ok, Vxpipe.Providers.Google.CredentialValidation} =
             Registry.fetch_capability("google", :credential_validation)

    assert {:ok, Vxpipe.Providers.Google.TTSSession} =
             Registry.fetch_capability("google", :tts)

    assert {:ok, Vxpipe.Providers.Google.STTSession} =
             Registry.fetch_capability("google", :stt)

    assert {:ok, Vxpipe.Providers.Rime} = Registry.fetch("rime")

    assert {:ok, Vxpipe.Providers.Rime.Credential} =
             Registry.fetch_capability("rime", :credential)

    assert {:ok, Vxpipe.Providers.Rime.CredentialValidation} =
             Registry.fetch_capability("rime", :credential_validation)

    assert {:ok, Vxpipe.Providers.Rime.TTSSession} =
             Registry.fetch_capability("rime", :tts)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("rime", :stt)

    assert {:ok, Vxpipe.Providers.Twilio} = Registry.fetch("twilio")

    assert {:ok, Vxpipe.Providers.Twilio.Credential} =
             Registry.fetch_capability("twilio", :credential)

    assert {:ok, Vxpipe.Providers.Twilio.CredentialValidation} =
             Registry.fetch_capability("twilio", :credential_validation)

    assert {:ok, Vxpipe.Providers.Twilio.ServiceProfile} =
             Registry.fetch_capability("twilio", :telephony)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("twilio", :stt)

    assert {:ok, Vxpipe.Providers.Zenmux} = Registry.fetch("zenmux")

    assert {:ok, Vxpipe.Providers.Zenmux.Credential} =
             Registry.fetch_capability("zenmux", :credential)

    assert {:ok, Vxpipe.Providers.Zenmux.CredentialValidation} =
             Registry.fetch_capability("zenmux", :credential_validation)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("zenmux", :telephony)
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
             "deepgram" => [:credential, :credential_validation, :stt, :tts],
             "google" => [:credential, :credential_validation, :stt, :tts],
             "morse" => [:sts, :stt, :tts],
             "rime" => [:credential, :credential_validation, :tts],
             "telnyx" => [:credential, :credential_validation, :telephony],
             "twilio" => [:credential, :credential_validation, :telephony],
             "zenmux" => [:credential, :credential_validation]
           }
  end

  test "credential schemas declare the accepted auth kind for consumers" do
    for provider <- ["deepgram", "google", "rime", "telnyx", "zenmux"] do
      assert {:ok, schema} = Registry.resolve_capability(provider, :credential)
      assert schema.auth_kind() == "api_key"
    end

    assert {:ok, twilio} = Registry.resolve_capability("twilio", :credential)
    assert twilio.auth_kind() == "account_sid_auth_token"
  end

  test "credential schemas declare ordered, safe inventory previews" do
    api_key_preview = [%{field: "api_key", label: "API key", display: :last_four}]

    for provider <- ["deepgram", "google", "rime", "telnyx", "zenmux"] do
      assert {:ok, schema} = Registry.resolve_capability(provider, :credential)
      assert schema.preview_fields() == api_key_preview
    end

    assert {:ok, twilio} = Registry.resolve_capability("twilio", :credential)

    assert twilio.preview_fields() == [
             %{field: "account_sid", label: "Account SID", display: :last_four},
             %{field: "auth_token", label: "Auth token", display: :masked}
           ]
  end
end
