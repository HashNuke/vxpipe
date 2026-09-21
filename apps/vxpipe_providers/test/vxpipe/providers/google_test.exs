defmodule Vxpipe.Providers.GoogleTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.{Credential, CredentialValidation}

  test "accepts only one bounded Google AI Studio API key" do
    assert :ok = Credential.validate("api_key", %{"api_key" => "private-key"})

    for payload <- [
          %{"api_key" => ""},
          %{"api_key" => "with space"},
          %{"api_key" => String.duplicate("x", 8_193)},
          %{"api_key" => "private-key", "other" => "value"}
        ] do
      assert {:error, :invalid_provider_auth} = Credential.validate("api_key", payload)
    end

    assert {:error, :invalid_provider_auth} = Credential.validate("other", %{})
  end

  test "describes the bounded model-list authentication probe" do
    assert {:ok, request} =
             CredentialValidation.request("api_key", %{"api_key" => "private-key"})

    assert request[:url] == "https://generativelanguage.googleapis.com/v1beta/models"
    assert request[:params] == [pageSize: 1]
    assert {"x-goog-api-key", "private-key"} in request[:headers]
    assert {:error, :provider_validation_unsupported} = CredentialValidation.request("other", %{})
  end
end
