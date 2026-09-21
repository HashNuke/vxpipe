defmodule Vxpipe.Providers.TwilioTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Twilio.{Credential, CredentialValidation}

  @sid "AC0123456789abcdef0123456789abcdef"

  test "accepts only a Twilio account SID and bounded UTF-8 auth token" do
    assert :ok =
             Credential.validate("account_sid_auth_token", %{
               "account_sid" => @sid,
               "auth_token" => "secret"
             })

    for payload <- [
          %{"account_sid" => "invalid", "auth_token" => "secret"},
          %{"account_sid" => @sid, "auth_token" => ""},
          %{"account_sid" => @sid, "auth_token" => String.duplicate("x", 4_097)},
          %{"account_sid" => @sid, "auth_token" => "secret", "extra" => "value"}
        ] do
      assert {:error, :invalid_provider_auth} =
               Credential.validate("account_sid_auth_token", payload)
    end
  end

  test "describes one bounded account authentication probe" do
    assert {:ok, request} =
             CredentialValidation.request("account_sid_auth_token", %{
               "account_sid" => @sid,
               "auth_token" => "secret"
             })

    assert request[:url] == "https://api.twilio.com/2010-04-01/Accounts/#{@sid}.json"
    assert {"authorization", "Basic " <> Base.encode64(@sid <> ":secret")} in request[:headers]
    assert {:error, :provider_validation_unsupported} = CredentialValidation.request("other", %{})
  end
end
