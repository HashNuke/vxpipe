defmodule Vxpipe.Providers.DeepgramTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Deepgram.{Credential, CredentialValidation}

  test "accepts only bounded Deepgram API-key credentials" do
    assert :ok = Credential.validate("api_key", %{"api_key" => "private-key"})

    for payload <- [
          %{"api_key" => ""},
          %{"api_key" => "with space"},
          %{"api_key" => String.duplicate("x", 8_193)},
          %{"api_key" => "key", "extra" => "value"}
        ] do
      assert {:error, :invalid_provider_auth} = Credential.validate("api_key", payload)
    end

    assert {:error, :invalid_provider_auth} =
             Credential.validate("other", %{"api_key" => "private-key"})
  end

  test "describes one bounded Deepgram credential probe" do
    assert {:ok, request} =
             CredentialValidation.request("api_key", %{"api_key" => "private-key"})

    assert request[:url] == "https://api.deepgram.com/v1/projects"
    assert {"authorization", "Token private-key"} in request[:headers]

    assert {:error, :provider_validation_unsupported} =
             CredentialValidation.request("other", %{"api_key" => "private-key"})
  end
end
