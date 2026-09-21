defmodule Vxpipe.Gateway.Integration.TelnyxVoiceAPITest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, EndLeg, LegReference, Submission}
  alias Vxpipe.Providers.Telnyx.Adapter, as: TelnyxAdapter

  @moduletag :integration
  @moduletag :telnyx_live
  @moduletag timeout: 30_000

  if System.get_env("VXPIPE_TELNYX_LIVE") != "1" do
    @moduletag skip: "set VXPIPE_TELNYX_LIVE=1 to place an authorized test call"
  end

  setup do
    {:ok,
     api_key: System.fetch_env!("TELNYX_API_KEY"),
     connection_id: System.fetch_env!("TELNYX_CONNECTION_ID"),
     from: System.fetch_env!("TELNYX_TEST_FROM"),
     media_url: System.fetch_env!("TELNYX_TEST_MEDIA_URL"),
     to: System.fetch_env!("TELNYX_TEST_DESTINATION"),
     webhook_url: System.fetch_env!("TELNYX_TEST_WEBHOOK_URL")}
  end

  test "Telnyx accepts the current dial/media contract for an authorized destination", context do
    leg_id = "live-#{System.unique_integer([:positive, :monotonic])}"

    request = %Dial{
      leg_id: leg_id,
      from: context.from,
      to: context.to,
      callback_url: context.webhook_url,
      media_url: context.media_url,
      answering_machine_detection: :disabled
    }

    options = [api_key: context.api_key, provider_connection_id: context.connection_id]

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: call_control_id,
              provider_call_leg_id: call_leg_id,
              provider_call_session_id: call_session_id
            }} = Adapter.dial(TelnyxAdapter, options, request)

    on_exit(fn ->
      _result =
        Adapter.end_leg(
          TelnyxAdapter,
          options,
          %EndLeg{
            leg: %LegReference{
              leg_id: leg_id,
              provider_call_control_id: call_control_id
            },
            reason: :test_complete
          }
        )
    end)

    assert is_binary(call_control_id) and call_control_id != ""
    assert is_binary(call_leg_id) and call_leg_id != ""
    assert is_binary(call_session_id) and call_session_id != ""
  end
end
