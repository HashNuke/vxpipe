defmodule Vxpipe.Providers.Telnyx.WebhookDecoderReviewTest do
  @moduledoc """
  Reproduction from the 2026-10-06 outgoing-call review
  (docs/milestones/outgoing-call-review-fixes.md). It failed when written.
  """

  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Providers.Telnyx.WebhookDecoder

  # Issue 2: Telnyx reports a callee declining with hangup_cause "call_rejected". The
  # outgoing-call spec defines a remote hangup before answer as `rejected`, which the
  # engine derives from a `:hangup` end reason; `:failed` records a decline as a failure.
  test "a callee decline (call_rejected) normalizes to a remote hangup, not a failure" do
    body =
      JSON.encode!(%{
        "data" => %{
          "record_type" => "event",
          "event_type" => "call.hangup",
          "id" => "event-1",
          "occurred_at" => "2026-10-06T10:00:00.000000Z",
          "payload" => %{
            "call_control_id" => "call-control-1",
            "call_leg_id" => "call-leg-1",
            "call_session_id" => "call-session-1",
            "connection_id" => "voice-application-1",
            "hangup_cause" => "call_rejected"
          }
        },
        "meta" => %{"attempt" => 1}
      })

    assert {:ok, %Event{kind: :ended, end_reason: reason}} =
             WebhookDecoder.decode(%Webhook{headers: %{}, body: body, received_at: 1_789_120_000})

    assert reason == :hangup
  end
end
