defmodule Vxpipe.Gateway.Integration.TwilioVoiceAPITest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, EndLeg, LegReference, Submission}
  alias Vxpipe.Providers.Twilio.Adapter, as: TwilioAdapter

  @moduletag :live_providers
  @moduletag :live_twilio
  @moduletag timeout: 30_000

  setup do
    {:ok,
     account_sid: System.fetch_env!("TWILIO_ACCOUNT_SID"),
     auth_token: System.fetch_env!("TWILIO_AUTH_TOKEN"),
     from: System.fetch_env!("TWILIO_TEST_FROM"),
     media_url: System.fetch_env!("TWILIO_TEST_MEDIA_URL"),
     to: System.fetch_env!("TWILIO_TEST_DESTINATION"),
     webhook_url: System.fetch_env!("TWILIO_TEST_WEBHOOK_URL")}
  end

  test "Twilio accepts one outbound request for an authorized destination", context do
    leg_id = "live-#{System.unique_integer([:positive, :monotonic])}"

    request = %Dial{
      leg_id: leg_id,
      from: context.from,
      to: context.to,
      callback_url: context.webhook_url,
      media_url: context.media_url,
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
