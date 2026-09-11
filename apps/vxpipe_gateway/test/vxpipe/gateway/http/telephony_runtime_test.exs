defmodule Vxpipe.Gateway.HTTP.TelephonyRuntimeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.Router
  alias Vxpipe.Gateway.Telephony.{MediaAdmission, OutgoingLegConnector, ServiceRegistry}

  test "mounting configured telephony gives the default call backend an outbound connector" do
    options =
      Router.init(
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
  end

  defp service do
    [
      id: "telnyx-primary",
      ingress_key: "outbound_ingress",
      scope: :application,
      provider: :telnyx,
      provider_connection_id: "voice-application-1",
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "test-api-key",
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test"
    ]
  end
end
