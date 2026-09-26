defmodule Vxpipe.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.OpenAI
  alias Vxpipe.Providers.OpenAI.{Credential, CredentialValidation}
  alias Vxpipe.Providers.Registry

  test "declares tenant credential and GPT-Live speech capabilities" do
    assert OpenAI.id() == "openai"

    assert OpenAI.capabilities() == %{
             credential: Credential,
             credential_validation: CredentialValidation,
             sts: Vxpipe.Providers.OpenAI.GPTLiveSession
           }

    assert {:ok, OpenAI} = Registry.fetch("openai")
    assert {:ok, Credential} = Registry.resolve_capability("openai", :credential)
    assert {:ok, CredentialValidation} =
             Registry.resolve_capability("openai", :credential_validation)

    assert {:ok, Vxpipe.Providers.OpenAI.GPTLiveSession} =
             Registry.fetch_capability("openai", :sts)
  end

  test "accepts exactly one printable, bounded API key and previews only its suffix" do
    assert Credential.auth_kind() == "api_key"
    assert Credential.preview_fields() == [
             %{field: "api_key", label: "API key", display: :last_four}
           ]

    assert :ok = Credential.validate("api_key", %{"api_key" => "private-key"})
    assert :ok = Credential.validate("api_key", %{"api_key" => String.duplicate("a", 8_192)})

    for payload <- [
          %{"api_key" => ""},
          %{"api_key" => "with space"},
          %{"api_key" => "with\nnewline"},
          %{"api_key" => String.duplicate("a", 8_193)},
          %{"api_key" => "private-key", "other" => "value"}
        ] do
      assert {:error, :invalid_provider_auth} = Credential.validate("api_key", payload)
    end

    assert {:error, :invalid_provider_auth} = Credential.validate("other", %{})
  end

  test "builds the fixed model-list authentication probe" do
    key = "private-openai-key"

    assert {:ok, request} = CredentialValidation.request("api_key", %{"api_key" => key})
    assert request[:url] == "https://api.openai.com/v1/models"
    assert request[:headers] == [
             {"authorization", "Bearer " <> key},
             {"accept", "application/json"}
           ]

    assert {:error, :provider_validation_unsupported} =
             CredentialValidation.request("other", %{"api_key" => key})
  end
end
