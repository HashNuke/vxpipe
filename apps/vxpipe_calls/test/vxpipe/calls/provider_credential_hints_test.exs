defmodule Vxpipe.Calls.ProviderCredentialHintsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.ProviderCredentialHints

  test "stores only fields selected by the provider preview policy" do
    assert ProviderCredentialHints.from_payload("deepgram", %{"api_key" => "private-1234"}) ==
             %{"api_key" => "1234"}

    assert ProviderCredentialHints.from_payload("twilio", %{
             "account_sid" => "AC11111111111111111111111111111111",
             "auth_token" => "private-token"
           }) == %{"account_sid" => "1111"}

    assert ProviderCredentialHints.from_payload("unknown", %{"api_key" => "private-1234"}) ==
             %{}
  end
end
