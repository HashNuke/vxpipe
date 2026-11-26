defmodule Vxpipe.Gateway.HTTP.TelephonyRuntimeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.CallAdmission

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    MediaAdmission,
    OutgoingLegConnector,
    ServiceRegistry
  }

  test "mounting configured telephony gives the default call backend an outbound connector" do
    options =
      Vxpipe.Gateway.TestTelephonyServiceRepository.router(
        call_admission: [enabled: true],
        telephony: [
          enabled: true,
          services: [service()],
          media_admission: MediaAdmission
        ]
      )

    assert %{backend: {CallAdmission, backend_options}} = options.call_admission

    assert {OutgoingLegConnector, connector_options} =
             Keyword.fetch!(backend_options, :outbound_leg_connector)

    assert %ServiceRegistry{enabled?: true} =
             Keyword.fetch!(connector_options, :service_registry)

    assert Keyword.fetch!(connector_options, :media_admission) == MediaAdmission

    assert Keyword.fetch!(connector_options, :media_supervisor) ==
             Vxpipe.Gateway.Telephony.MediaSupervisor
  end

  test "telephony ingress shares the ordinary admission recording configuration" do
    recording = [enabled: true]

    options =
      Vxpipe.Gateway.TestTelephonyServiceRepository.router(
        call_admission: [enabled: true, backend: {CallAdmission, [recording: recording]}],
        telephony: [
          enabled: true,
          services: [service()],
          media_admission: MediaAdmission
        ]
      )

    assert %{backend: {CallAdmission, ordinary}} = options.call_admission
    assert Keyword.fetch!(ordinary, :recording) == recording

    assert {CallIngress, ingress} = options.telephony.handler
    assert {CallAdmission, incoming} = Keyword.fetch!(ingress, :backend)
    assert Keyword.fetch!(incoming, :recording) == recording
  end

  test "an explicit telephony recording configuration stays authoritative" do
    ordinary = [enabled: true]
    explicit = [enabled: false]

    options =
      Vxpipe.Gateway.TestTelephonyServiceRepository.router(
        call_admission: [enabled: true, backend: {CallAdmission, [recording: ordinary]}],
        telephony: [
          enabled: true,
          services: [service()],
          media_admission: MediaAdmission,
          handler:
            {CallIngress, [backend: {CallAdmission, [recording: explicit, custom: :retained]}]}
        ]
      )

    assert {CallIngress, ingress} = options.telephony.handler
    assert {CallAdmission, incoming} = Keyword.fetch!(ingress, :backend)
    assert Keyword.fetch!(incoming, :recording) == explicit
    assert Keyword.fetch!(incoming, :custom) == :retained
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
