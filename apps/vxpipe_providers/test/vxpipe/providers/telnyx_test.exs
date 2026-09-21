defmodule Vxpipe.Providers.TelnyxTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Telnyx.{Credential, CredentialValidation}

  test "accepts a bounded API key and optional 32-byte webhook verification key" do
    public_key = Base.encode64(:binary.copy(<<1>>, 32))
    assert :ok = Credential.validate("api_key", %{"api_key" => "private-key"})

    assert :ok =
             Credential.validate("api_key", %{
               "api_key" => "private-key",
               "public_key" => public_key
             })

    for payload <- [
          %{"api_key" => ""},
          %{"api_key" => "with space"},
          %{"api_key" => String.duplicate("x", 4_097)},
          %{"api_key" => "private-key", "public_key" => "bad"},
          %{"api_key" => "private-key", "other" => "value"}
        ] do
      assert {:error, :invalid_provider_auth} = Credential.validate("api_key", payload)
    end
  end

  test "describes the existing bounded read-only credential probe" do
    assert {:ok, request} =
             CredentialValidation.request("api_key", %{"api_key" => "private-key"})

    assert request[:url] == "https://api.telnyx.com/v2/call_control_applications"
    assert request[:params] == [{"page[size]", 1}]
    assert {"authorization", "Bearer private-key"} in request[:headers]
    assert {:error, :provider_validation_unsupported} = CredentialValidation.request("other", %{})
  end
end
