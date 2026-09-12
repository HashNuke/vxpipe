defmodule Vxpipe.Gateway.Telephony.IncomingLegActivationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    IncomingLegActivation,
    IncomingLegActivationResult,
    MediaAdmission
  }

  alias Vxpipe.Gateway.TestTelephonyCallBackend

  setup do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})
    admission = start_supervised!({MediaAdmission, name: nil})
    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    %{admission: admission, claim: TestTelephonyCallBackend.claim(backend), leg: leg}
  end

  test "answers through the pinned service with one exact media admission", context do
    assert {:ok,
            %IncomingLegActivationResult{
              binding: binding,
              media_url: media_url,
              submission: submission,
              usage: usage
            }} =
             IncomingLegActivation.activate(
               service("accept"),
               context.claim,
               "rinc_phone-1",
               context.leg,
               media_admission: context.admission,
               leg_id: fn -> "tleg-incoming-1" end,
               usage_clock: fn -> ~U[2026-09-12 05:00:00.000Z] end,
               usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
             )

    assert submission.status == :accepted
    assert usage.attempt.attempt_id == "tleg-incoming-1"
    assert binding.client_state_leg_id == "tleg-incoming-1"
    assert binding.incarnation_id == "rinc_phone-1"

    assert_receive {:test_telephony_answer, request}
    assert_receive {:test_usage_observations, [started]}
    assert started.measurement.component == "carrier_legs"
    assert started.attribution.participant_id == context.claim.participant_id
    assert started.provider.operation_id == "call-leg-1"
    assert started.provider.session_id == "call-session-1"
    assert media_url == request.media_url
    assert request.leg.leg_id == "tleg-incoming-1"
    assert request.leg.provider_call_control_id == "call-control-1"

    assert %URI{scheme: "wss", host: "voice.example.test", path: path} =
             URI.parse(request.media_url)

    assert ["", "voice", "api", "telephony", "telnyx", "ingress_telnyx_primary", "media", token] =
             String.split(path, "/")

    assert {:ok, ^binding} =
             MediaAdmission.consume(context.admission, "ingress_telnyx_primary", token)
  end

  test "prepares synchronous Twilio media instructions without inventing a command call",
       context do
    claim = %{
      context.claim
      | provider: :twilio,
        provider_connection_id: "AC00000000000000000000000000000000",
        provider_call_control_id: "CA00000000000000000000000000000000",
        provider_call_leg_id: "CA00000000000000000000000000000000",
        provider_call_session_id: nil
    }

    assert {:ok,
            %IncomingLegActivationResult{
              binding: binding,
              media_url: media_url,
              submission: %{status: :accepted}
            }} =
             IncomingLegActivation.activate(
               twilio_service(),
               claim,
               "rinc_phone-2",
               context.leg,
               media_admission: context.admission,
               leg_id: fn -> "tleg-twilio-incoming-1" end
             )

    assert binding.provider == :twilio
    assert binding.provider_call_session_id == nil

    assert %URI{scheme: "wss", host: "voice.example.test", path: path} = URI.parse(media_url)

    assert ["", "voice", "api", "telephony", "twilio", "ingress_twilio_primary", "media", token] =
             String.split(path, "/")

    assert {:ok, ^binding} =
             MediaAdmission.consume(context.admission, "ingress_twilio_primary", token)
  end

  test "revokes media admission when the carrier rejects the answer", context do
    assert {:error, :command_rejected} =
             IncomingLegActivation.activate(
               service("reject"),
               context.claim,
               "rinc_phone-1",
               context.leg,
               media_admission: context.admission,
               leg_id: fn -> "tleg-incoming-2" end,
               usage_clock: fn -> ~U[2026-09-12 05:30:00.000Z] end,
               usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
             )

    assert_receive {:test_telephony_answer, request}
    assert_receive {:test_usage_observations, [started]}
    assert_receive {:test_usage_observations, [failed]}
    assert started.outcome == :in_progress
    assert failed.outcome == :failed
    assert failed.measurement == nil

    token =
      request.media_url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last()

    assert {:error, :invalid_media_token} =
             MediaAdmission.consume(context.admission, "ingress_telnyx_primary", token)
  end

  defp service(api_key) do
    assert {:ok, service} =
             ConfiguredService.new(
               id: "primary-phone",
               ingress_key: "ingress_telnyx_primary",
               scope: {:tenant, "AAAAAAAAAAAAAAAA"},
               provider: :telnyx,
               provider_connection_id: "voice-application-1",
               public_key: Base.encode64(:binary.copy(<<1>>, 32)),
               api_key: api_key,
               public_base_url: "https://voice.example.test/voice",
               adapter: Vxpipe.Gateway.TestTelephonyAdapter
             )

    service
  end

  defp twilio_service do
    assert {:ok, service} =
             ConfiguredService.new(
               id: "primary-phone",
               ingress_key: "ingress_twilio_primary",
               scope: {:tenant, "AAAAAAAAAAAAAAAA"},
               provider: :twilio,
               account_sid: "AC00000000000000000000000000000000",
               auth_token: "twilio-test-auth-token",
               public_base_url: "https://voice.example.test/voice"
             )

    service
  end
end
