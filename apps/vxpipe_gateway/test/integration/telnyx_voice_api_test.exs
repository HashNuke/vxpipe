defmodule Vxpipe.Gateway.Integration.TelnyxVoiceAPITest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Adapter, Dial, EndLeg, LegReference, Submission}
  alias Vxpipe.Gateway.TestTelephonyServiceRepository
  alias Vxpipe.Providers.Telnyx.Adapter, as: TelnyxAdapter
  alias Vxpipe.Providers.Telnyx.PublicEndpoint

  @moduletag :live_providers
  @moduletag :live_telnyx
  @moduletag timeout: 30_000

  setup do
    api_key = System.fetch_env!("TELNYX_API_KEY")
    app_id = System.fetch_env!("TELNYX_APP_ID")

    service =
      TestTelephonyServiceRepository.configured(
        id: "live-telnyx",
        ingress_key: "live-telnyx",
        scope: {:tenant, "livetelnyxtest00"},
        provider: :telnyx,
        provider_connection_id: app_id,
        api_key: api_key,
        public_key: System.fetch_env!("TELNYX_PUBLIC_KEY"),
        public_base_url: System.fetch_env!("TELEPHONY_TEST_PUBLIC_URL")
      )

    {:ok,
     api_key: api_key,
     app_id: app_id,
     from: System.fetch_env!("TELNYX_TEST_FROM"),
     service: service,
     to: System.fetch_env!("TELNYX_TEST_DESTINATION")}
  end

  test "Telnyx accepts the current dial/media contract for an authorized destination", context do
    leg_id = "live-#{System.unique_integer([:positive, :monotonic])}"

    request = %Dial{
      leg_id: leg_id,
      from: context.from,
      to: context.to,
      callback_url: PublicEndpoint.event_url(context.service),
      media_url: PublicEndpoint.media_url(context.service, leg_id),
      answering_machine_detection: :disabled
    }

    options = [api_key: context.api_key, provider_connection_id: context.app_id]

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
