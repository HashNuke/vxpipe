defmodule Vxpipe.Providers.JevTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Jev
  alias Vxpipe.Providers.Jev.{Credential, CredentialValidation}
  alias Vxpipe.Providers.Registry

  test "declares tenant credential and System One decisions capabilities" do
    assert Jev.id() == "jev"

    assert Jev.capabilities() == %{
             credential: Credential,
             credential_validation: CredentialValidation,
             decisions: Vxpipe.Providers.Jev.Decisions
           }

    assert {:ok, Jev} = Registry.fetch("jev")
    assert {:ok, Credential} = Registry.resolve_capability("jev", :credential)

    assert {:ok, CredentialValidation} =
             Registry.resolve_capability("jev", :credential_validation)

    assert {:ok, Vxpipe.Providers.Jev.Decisions} =
             Registry.fetch_capability("jev", :decisions)
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
    key = "private-jev-key"

    assert {:ok, request} = CredentialValidation.request("api_key", %{"api_key" => key})
    assert request[:url] == "https://api.typesafe.ai/v1/models"

    assert request[:headers] == [
             {"authorization", "Bearer " <> key},
             {"accept", "application/json"}
           ]

    assert {:error, :provider_validation_unsupported} =
             CredentialValidation.request("other", %{"api_key" => key})
  end
end
