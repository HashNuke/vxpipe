defmodule Vxpipe.Gateway.ApplicationConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Gateway.{Application, CallAdmission, CallCleanupReconciler, CallCreation}
  alias Vxpipe.Gateway.Telephony.CallIngress

  test "one managed setting reaches default HTTP, MCP and incoming backends" do
    archive = [enabled: true, writer: {SyntheticArchive, []}]

    settings = [
      managed_cleanup: [enabled: true],
      http: [
        enabled: false,
        call_admission: [enabled: true, backend: {CallAdmission, [archive: archive]}],
        telephony: [enabled: true, services: [service()]]
      ]
    ]

    endpoint =
      settings
      |> Application.http_options()
      |> Vxpipe.Gateway.TestTelephonyServiceRepository.endpoint()

    assert {CallAdmission, http} = endpoint.router.call_admission.backend
    assert {CallCreation, creation} = endpoint.router.call_creation.backend
    assert {CallIngress, ingress} = endpoint.router.telephony.handler
    assert {CallAdmission, incoming} = Keyword.fetch!(ingress, :backend)

    for options <- [http, creation, incoming, endpoint.mcp.call_options] do
      assert Keyword.fetch!(options, :managed_cleanup)
      assert Keyword.fetch!(options, :archive) == archive
    end
  end

  test "incoming explicit options remain authoritative and custom handlers/backends stay unchanged" do
    common = [archive: [enabled: true], cleanup_options: [timeout_ms: 90]]
    incoming = [archive: [enabled: false], cleanup_options: [timeout_ms: 70], custom: :retained]

    http = [
      call_admission: [backend: {CallAdmission, common}],
      telephony: [handler: {CallIngress, [backend: {CallAdmission, incoming}]}]
    ]

    configured = Application.http_options(managed_cleanup: [enabled: true], http: http)
    {CallIngress, handler} = configured |> Keyword.fetch!(:telephony) |> Keyword.fetch!(:handler)
    assert {CallAdmission, actual} = Keyword.fetch!(handler, :backend)
    assert Keyword.delete(actual, :managed_cleanup) == incoming
    assert Keyword.fetch!(actual, :managed_cleanup)

    for handler <- [
          {CustomIngress, :context},
          {CallIngress, [backend: {CustomBackend, :context}]}
        ] do
      http = [call_admission: [backend: {CustomBackend, :web}], telephony: [handler: handler]]
      configured = Application.http_options(managed_cleanup: [enabled: true], http: http)
      assert Map.new(configured) == Map.new(http)
    end
  end

  test "unmanaged composition preserves the configured backends" do
    http = [
      call_admission: [backend: {CallAdmission, [custom: true]}],
      telephony: [enabled: false]
    ]

    assert Application.http_options(http: http) == http
    assert Application.http_options(managed_cleanup: [enabled: false], http: http) == http
  end

  test "durable cleanup starts one named reconciler even without a Gateway listener" do
    settings = [
      managed_cleanup: [
        enabled: true,
        reconciler: [calls_options: [call_repository: {__MODULE__, self()}]]
      ],
      http: [enabled: false]
    ]

    children = Application.child_specs(settings)

    assert [{CallCleanupReconciler, options}] =
             Enum.filter(children, &match?({CallCleanupReconciler, _}, &1))

    refute Enum.any?(children, &match?({Vxpipe.Gateway.HTTP.Supervisor, _}, &1))
    assert Keyword.fetch!(options, :name) == CallCleanupReconciler
    tracker = start_supervised!({CallCleanupReconciler, options})
    assert Process.whereis(CallCleanupReconciler) == tracker
    assert_receive {:cleanup_scan, nil, 25}

    for configured <- [
          [http: [enabled: false]],
          [managed_cleanup: [enabled: false], http: [enabled: false]]
        ] do
      refute Enum.any?(
               Application.child_specs(configured),
               &match?({CallCleanupReconciler, _}, &1)
             )
    end
  end

  def scan_call_cleanup(observer, cursor, limit) do
    send(observer, {:cleanup_scan, cursor, limit})
    {:ok, %{items: [], next_cursor: nil}}
  end

  defp service do
    [
      id: "telnyx-primary",
      ingress_key: "outbound_ingress",
      scope: {:tenant, "AAAAAAAAAAAAAAAA"},
      provider: :telnyx,
      provider_connection_id: "voice-application-1",
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "synthetic-key",
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test"
    ]
  end
end
