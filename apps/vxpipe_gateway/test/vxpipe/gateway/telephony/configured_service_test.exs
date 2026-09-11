defmodule Vxpipe.Gateway.Telephony.ConfiguredServiceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.ConfiguredService
  alias Vxpipe.Gateway.Telephony.Telnyx.Adapter

  test "pins a complete Telnyx command and public callback configuration" do
    assert {:ok, service} = ConfiguredService.new(valid_options())

    assert service.adapter == Adapter

    assert service.adapter_options == [
             api_key: "test-api-key",
             provider_connection_id: "voice-application-1"
           ]

    assert service.public_base_url == "https://voice.example.test/voice"
    assert service.media_token_ttl_ms == 60_000
    refute inspect(service) =~ "test-api-key"
  end

  test "rejects missing secrets and non-TLS or ambiguous public URLs" do
    for options <- [
          Keyword.delete(valid_options(), :api_key),
          Keyword.delete(valid_options(), :public_base_url),
          Keyword.put(valid_options(), :public_base_url, "http://voice.example.test"),
          Keyword.put(valid_options(), :public_base_url, "https://user@voice.example.test"),
          Keyword.put(
            valid_options(),
            :public_base_url,
            "https://voice.example.test?token=secret"
          ),
          Keyword.put(valid_options(), :public_base_url, "not-a-url")
        ] do
      assert {:error, :invalid_telephony_service_configuration} =
               ConfiguredService.new(options)
    end
  end

  defp valid_options do
    [
      id: "telnyx-primary",
      ingress_key: "ingress_telnyx_primary",
      scope: {:tenant, "tenantkey1234567"},
      provider: :telnyx,
      provider_connection_id: "voice-application-1",
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "test-api-key",
      public_base_url: "https://voice.example.test/voice/"
    ]
  end
end
