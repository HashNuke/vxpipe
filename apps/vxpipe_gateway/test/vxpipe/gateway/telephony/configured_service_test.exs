defmodule Vxpipe.Gateway.Telephony.ConfiguredServiceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.ConfiguredService
  alias Vxpipe.Providers.Telnyx.Adapter
  alias Vxpipe.Providers.Twilio.Adapter, as: TwilioAdapter

  test "rejects application-scoped carrier credentials" do
    for options <- [valid_options(), valid_twilio_options()] do
      assert {:error, :invalid_telephony_service_configuration} =
               ConfiguredService.new(Keyword.put(options, :scope, :application))
    end
  end

  test "pins a complete Telnyx command and public callback configuration" do
    assert {:ok, service} = ConfiguredService.new(valid_options())

    assert service.adapter == Adapter

    assert service.adapter_options == [
             api_key: "test-api-key",
             provider_connection_id: "voice-application-1"
           ]

    assert service.public_base_url == "https://voice.example.test/voice"
    assert service.media_token_ttl_ms == 60_000
    assert service.outbound_number == "+15550001000"
    assert service.answering_machine_detection == :disabled
    refute inspect(service) =~ "test-api-key"
  end

  test "accepts the closed provider answering-machine detection setting" do
    assert {:ok, service} =
             valid_options()
             |> Keyword.put(:answering_machine_detection, :detect)
             |> ConfiguredService.new()

    assert service.answering_machine_detection == :detect

    assert {:error, :invalid_telephony_service_configuration} =
             valid_options()
             |> Keyword.put(:answering_machine_detection, :premium)
             |> ConfiguredService.new()
  end

  test "pins Twilio account authentication without a fictitious connection id" do
    assert {:ok, service} = ConfiguredService.new(valid_twilio_options())

    assert service.identity.provider == :twilio
    assert service.identity.provider_connection_id == "AC00000000000000000000000000000000"
    assert service.adapter == TwilioAdapter

    assert service.adapter_options == [
             account_sid: "AC00000000000000000000000000000000",
             auth_token: "twilio-test-auth-token"
           ]

    assert service.verifier_options == [auth_token: "twilio-test-auth-token"]
    refute inspect(service) =~ "twilio-test-auth-token"
  end

  test "rejects malformed or mixed Twilio credentials" do
    for options <- [
          Keyword.put(valid_twilio_options(), :account_sid, "not-an-account-sid"),
          Keyword.put(valid_twilio_options(), :auth_token, ""),
          Keyword.put(valid_twilio_options(), :api_key, "telnyx-secret"),
          Keyword.put(
            valid_twilio_options(),
            :public_key,
            Base.encode64(:binary.copy(<<1>>, 32))
          ),
          Keyword.put(valid_twilio_options(), :provider_connection_id, "voice-application")
        ] do
      assert {:error, :invalid_telephony_service_configuration} =
               ConfiguredService.new(options)
    end
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
          Keyword.put(valid_options(), :outbound_number, "555-000-1000"),
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
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test/voice/"
    ]
  end

  defp valid_twilio_options do
    [
      id: "twilio-primary",
      ingress_key: "ingress_twilio_primary",
      scope: {:tenant, "tenantkey1234567"},
      provider: :twilio,
      account_sid: "AC00000000000000000000000000000000",
      auth_token: "twilio-test-auth-token",
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test/voice/"
    ]
  end
end
