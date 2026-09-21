defmodule Vxpipe.Providers.ZenmuxTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Zenmux.{Credential, CredentialValidation}

  test "accepts only one bounded Zenmux API key" do
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

  test "describes the bounded model-list credential probe" do
    assert {:ok, request} =
             CredentialValidation.request("api_key", %{"api_key" => "private-key"})

    assert request[:url] == "https://zenmux.ai/api/v1/models"
    assert {"authorization", "Bearer private-key"} in request[:headers]
    assert {:error, :provider_validation_unsupported} = CredentialValidation.request("other", %{})
  end
end
