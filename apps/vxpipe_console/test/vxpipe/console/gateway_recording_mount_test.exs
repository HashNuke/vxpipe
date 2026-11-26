defmodule Vxpipe.Console.GatewayRecordingMountTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.{Application, CallAdmission}
  alias Vxpipe.Gateway.Telephony.{CallIngress, MediaAdmission}

  test "console order gives ordinary web and default telephony the exact same writer" do
    recording = [
      enabled: true,
      targets: [:room_track, :individual_tracks],
      writer: {TestWriter, []}
    ]

    gateway_settings = [
      managed_cleanup: [enabled: true],
      http: [
        enabled: false,
        call_admission: [enabled: true, backend: {CallAdmission, []}],
        telephony: [enabled: true, services: [service()], media_admission: MediaAdmission]
      ]
    ]

    # New Console order: inject recording before http_options so managed
    # cleanup shares the exact same writer.
    injected =
      update_in(gateway_settings, [:http, :call_admission], fn call_admission ->
        Keyword.update!(call_admission, :backend, fn
          {CallAdmission, options} -> {CallAdmission, Keyword.put(options, :recording, recording)}
        end)
      end)

    http = Application.http_options(injected)

    # Managed path already carries recording before Router fallback.
    telephony_handler = http |> Keyword.fetch!(:telephony) |> Keyword.fetch!(:handler)
    assert {CallIngress, ingress} = telephony_handler
    assert {CallAdmission, incoming} = Keyword.fetch!(ingress, :backend)
    assert Keyword.fetch!(incoming, :recording) == recording

    # Real normal composition through Router.
    router =
      Vxpipe.Gateway.TestTelephonyServiceRepository.router(
        call_admission: Keyword.fetch!(http, :call_admission),
        telephony: Keyword.fetch!(http, :telephony)
      )

    assert %{backend: {CallAdmission, ordinary}} = router.call_admission
    assert Keyword.fetch!(ordinary, :recording) == recording

    assert {CallIngress, final_ingress} = router.telephony.handler
    assert {CallAdmission, final_incoming} = Keyword.fetch!(final_ingress, :backend)
    assert Keyword.fetch!(final_incoming, :recording) == recording
    assert Keyword.fetch!(final_incoming, :recording) === Keyword.fetch!(ordinary, :recording)
  end

  defp service do
    [
      id: "telnyx-primary",
      ingress_key: "outbound_ingress",
      scope: {:tenant, "AAAAAAAAAAAAAAAA"},
      provider: :telnyx,
      provider_connection_id: "voice-application-1",
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "test-api-key",
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test"
    ]
  end
end
