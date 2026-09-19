defmodule Vxpipe.Calls.TelnyxProviderAuthTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.ProviderAuth

  test "Telnyx accepts an optional scoped verification key without opening other payloads" do
    key = Base.encode64(:binary.copy(<<1>>, 32))
    payload = %{"api_key" => "synthetic-key", "public_key" => key}
    assert :ok = ProviderAuth.validate("telnyx", "api_key", payload)
    assert :ok = ProviderAuth.validate("telnyx", "api_key", Map.delete(payload, "public_key"))

    for invalid <- [nil, "", "bad-key", Base.encode64(:binary.copy(<<1>>, 31))] do
      assert {:error, :invalid_provider_auth} =
               ProviderAuth.validate("telnyx", "api_key", %{payload | "public_key" => invalid})
    end

    assert {:error, :invalid_provider_auth} =
             ProviderAuth.validate("google", "api_key", payload)

    assert {:error, :invalid_provider_auth} =
             ProviderAuth.validate("telnyx", "api_key", Map.put(payload, "owner", "platform"))
  end
end
