defmodule Vxpipe.Gateway.Integration.TwilioVoiceAPITest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, EndLeg, LegReference, Submission}
  alias Vxpipe.Gateway.TestTelephonyServiceRepository
  alias Vxpipe.Providers.Twilio.Adapter, as: TwilioAdapter
  alias Vxpipe.Providers.Twilio.PublicEndpoint

  @moduletag :live_providers
  @moduletag :live_twilio
  @moduletag timeout: 30_000

  setup do
    account_sid = System.fetch_env!("TWILIO_ACCOUNT_SID")
    auth_token = System.fetch_env!("TWILIO_AUTH_TOKEN")

    service =
      TestTelephonyServiceRepository.configured(
        id: "live-twilio",
        ingress_key: "live-twilio",
        scope: {:tenant, "livetwiliotest00"},
        provider: :twilio,
        account_sid: account_sid,
        auth_token: auth_token,
        public_base_url: System.fetch_env!("TELEPHONY_TEST_PUBLIC_URL")
      )

    {:ok,
     account_sid: account_sid,
     auth_token: auth_token,
     from: System.fetch_env!("TWILIO_TEST_FROM"),
     service: service,
     to: System.fetch_env!("TWILIO_TEST_DESTINATION")}
  end

  test "Twilio accepts one outbound request for an authorized destination", context do
    leg_id = "live-#{System.unique_integer([:positive, :monotonic])}"

    request = %Dial{
      leg_id: leg_id,
      from: context.from,
      to: context.to,
      callback_url: PublicEndpoint.event_url(context.service, leg_id),
      media_url: PublicEndpoint.media_url(context.service, leg_id),
      answering_machine_detection: :disabled
    }

    options = [account_sid: context.account_sid, auth_token: context.auth_token]

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: call_sid,
              provider_call_leg_id: call_sid,
              provider_call_session_id: nil
            }} = Adapter.dial(TwilioAdapter, options, request)

    on_exit(fn ->
      _result =
        Adapter.end_leg(
          TwilioAdapter,
          options,
          %EndLeg{
            leg: %LegReference{
              leg_id: leg_id,
              provider_call_control_id: call_sid
            },
            reason: :test_complete
          }
        )
    end)

    assert String.starts_with?(call_sid, "CA")
    assert byte_size(call_sid) == 34
  end
end
