defmodule Vxpipe.Gateway.CallAdmission.CallEngineOptionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions

  test "passes trusted recording configuration to call startup" do
    recording = [
      enabled: true,
      targets: [:full_mix],
      writer: {TestWriter, [object_store: TestStore]},
      maximum_pull_frames: 4
    ]

    assert CallEngineOptions.build(recording: recording) == [
             archive: [enabled: false],
             recording: recording
           ]
  end

  test "managed startup scopes the real outgoing connector to its trusted call" do
    connector = Vxpipe.Gateway.Telephony.OutgoingLegConnector
    call = %{tenant_key: "tenant", id: "call", room_id: "room"}

    options = [
      managed_cleanup: true,
      outbound_leg_connector: {connector, [media_admission: :media]}
    ]

    assert {:ok, runtime} = CallEngineOptions.build(options, call)
    assert {^connector, scoped} = Keyword.fetch!(runtime, :outbound_leg_connector)

    assert Keyword.fetch!(scoped, :cleanup_scope) == %{
             tenant_key: "tenant",
             call_id: "call",
             room_id: "room"
           }

    assert Keyword.fetch!(scoped, :media_admission) == :media
    assert Keyword.fetch!(Keyword.fetch!(scoped, :cleanup_options), :calls_options) == options
  end

  test "managed startup rejects a custom connector that cannot attest cleanup ownership" do
    assert {:error, :cleanup_connector_unavailable} =
             CallEngineOptions.build(
               [managed_cleanup: true, outbound_leg_connector: {CustomConnector, []}],
               %{tenant_key: "tenant", id: "call", room_id: "room"}
             )
  end

  test "unmanaged calls preserve custom connectors without adding cleanup scope" do
    options = [outbound_leg_connector: {CustomConnector, [custom: true]}]

    assert {:ok, runtime} =
             CallEngineOptions.build(options, %{tenant_key: "tenant", id: "call", room_id: "room"})

    assert runtime == CallEngineOptions.build(options)
  end
end
