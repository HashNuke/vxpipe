defmodule Vxpipe.Gateway.Telephony.IncomingLegActivationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.{ConfiguredService, IncomingLegActivation, MediaAdmission}
  alias Vxpipe.Gateway.TestTelephonyCallBackend

  setup do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})
    admission = start_supervised!({MediaAdmission, name: nil})
    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    %{admission: admission, claim: TestTelephonyCallBackend.claim(backend), leg: leg}
  end

  test "answers through the pinned service with one exact media admission", context do
    assert {:ok, binding, submission} =
             IncomingLegActivation.activate(
               service("accept"),
               context.claim,
               "rinc_phone-1",
               context.leg,
               media_admission: context.admission,
               leg_id: fn -> "tleg-incoming-1" end
             )

    assert submission.status == :accepted
    assert binding.client_state_leg_id == "tleg-incoming-1"
    assert binding.incarnation_id == "rinc_phone-1"

    assert_receive {:test_telephony_answer, request}
    assert request.leg.leg_id == "tleg-incoming-1"
    assert request.leg.provider_call_control_id == "call-control-1"

    assert %URI{scheme: "wss", host: "voice.example.test", path: path} =
             URI.parse(request.media_url)

    assert ["", "voice", "api", "telephony", "telnyx", "ingress_telnyx_primary", "media", token] =
             String.split(path, "/")

    assert {:ok, ^binding} =
             MediaAdmission.consume(context.admission, "ingress_telnyx_primary", token)
  end

  test "revokes media admission when the carrier rejects the answer", context do
    assert {:error, :command_rejected} =
             IncomingLegActivation.activate(
               service("reject"),
               context.claim,
               "rinc_phone-1",
               context.leg,
               media_admission: context.admission,
               leg_id: fn -> "tleg-incoming-2" end
             )

    assert_receive {:test_telephony_answer, request}

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
end
