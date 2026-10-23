defmodule Vxpipe.Providers.MorseCodeApi.CredentialTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.MorseCodeApi.Credential

  test "accepts caller-chosen header-safe keys without provider ownership rules" do
    for key <- ["synthetic", "my compatibility key"] do
      assert :ok = Credential.validate("api_key", %{"api_key" => key})
    end

    for key <- [
          "clé-morse",
          nil,
          "",
          "  ",
          "\r\ninjected: value",
          <<0>>,
          <<127>>,
          <<255>>,
          String.duplicate("x", 8_193)
        ] do
      assert {:error, :invalid_provider_auth} =
               Credential.validate("api_key", %{"api_key" => key})
    end

    assert {:error, :invalid_provider_auth} = Credential.validate("bearer", %{"api_key" => "key"})

    assert {:error, :invalid_provider_auth} =
             Credential.validate("api_key", %{
               "api_key" => "key",
               "endpoint" => "https://example.com"
             })

    assert Credential.auth_kind() == "api_key"

    assert Credential.preview_fields() == [
             %{field: "api_key", label: "API key", display: :last_four}
           ]
  end
end
