defmodule Vxpipe.CallEngine.Readiness.CollectorTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.{RoomCapabilitySupervisor, TestReadinessAdapter}
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Speech.CapabilityTree
  alias Vxpipe.CallEngine.{RoomMixer, TestSpeechToTextTransport}

  test "combines actual provider and room evidence and rejects a changed policy binding" do
    identity = [tenant_id: "tenant-ready", room_id: "room-ready", incarnation_id: "inc-ready"]

    mixer =
      start_supervised!(
        {RoomMixer,
         identity ++
           [
             register: false,
             sample_rate: 48_000,
             channels: 1,
             frame_samples: 960,
             maximum_buffered_timestamps: 8,
             maximum_sink_frames: 8
           ]}
      )

    assert {:ok, provider} =
             Flux.new(
               api_key: "fixture-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    stt =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             participant_id: "caller",
             connection_id: "connection",
             speech_scope: CapabilityTree.scope(tree),
             provider:
               {Flux.Session,
                model: provider.model,
                encoding: provider.encoding,
                sample_rate: provider.sample_rate},
             provider_private: [
               config: provider,
               wire_module: TestSpeechToTextTransport,
               wire_options: [observer: self()]
             ]
           ]}
      )

    assert_receive {:test_stt_transport_started, transport, _connection}

    policy = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller", "support"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }

    assert :ok = Enforcer.apply(mixer, policy, 1_000)
    assert :ok = Enforcer.apply(stt, policy, 1_000)
    assert {:ok, mixer_resource, :ready} = RoomMixer.readiness(mixer)
    assert {:ok, stt_resource, :preparing} = SpeechToText.readiness(stt)
    collector = collector([mixer_resource, stt_resource])

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :preparing, blockers: [%{kind: :speech_to_text}]}}

    TestSpeechToTextTransport.deliver(
      transport,
      ~s({"type":"Connected","request_id":"connected","sequence_id":0})
    )

    assert_receive {:vxpipe_stt_signal, ^stt, _, %Signal{kind: :connected}}
    assert :ok = Collector.refresh(collector)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}

    assert :ok =
             Enforcer.apply(
               mixer,
               %{policy | revision: 1, effective: %{policy.effective | audio_routes: %{}}},
               1_000
             )

    assert :ok = Collector.refresh(collector)

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :failed, failure: :binding_changed}}

    assert {:ok, revised_mixer, :ready} = RoomMixer.readiness(mixer)
    assert revised_mixer.generation == mixer_resource.generation
    assert {:ok, _diff} = Collector.reconcile(collector, "attempt", [revised_mixer, stt_resource])
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}
    refute_receive {:test_stt_transport_started, _, _}
  end

  test "collects every required binding asynchronously and retains ready evidence on reconcile" do
    first = adapter("first")
    second = adapter("second")
    resources = Enum.map([first, second], &TestReadinessAdapter.resource/1)
    collector = collector(resources)
    assert_receive {:readiness_requested, ^first}
    assert_receive {:readiness_requested, ^second}
    assert %{status: :preparing} = Collector.snapshot(collector)

    :ok = TestReadinessAdapter.reply(first, :ready)
    :ok = TestReadinessAdapter.reply(second, :preparing)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :preparing, blockers: [_]}}
    assert :ok = Collector.refresh(collector)
    assert_receive {:readiness_requested, ^first}
    assert_receive {:readiness_requested, ^second}
    :ok = TestReadinessAdapter.reply(first, :ready)
    :ok = TestReadinessAdapter.reply(second, :ready)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}

    assert {:ok, %{prepare: [], remove: [], retain: retained}} =
             Collector.reconcile(collector, "next-attempt", resources)

    assert MapSet.new(retained) == MapSet.new(resources)

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :ready, attempt_id: "next-attempt"}}

    refute_receive {:readiness_requested, _}
  end

  test "a ready resource dying revokes readiness even without another probe" do
    source = adapter("source")
    resource = TestReadinessAdapter.resource(source)
    collector = collector([resource])
    assert_receive {:readiness_requested, ^source}
    :ok = TestReadinessAdapter.reply(source, :ready)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}

    :ok = stop_supervised({TestReadinessAdapter, "source"})
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}
    assert %{status: :failed} = Collector.snapshot(collector)
  end

  test "rechecks preparing resources automatically and stops polling once ready" do
    source = adapter("source")
    collector = collector([TestReadinessAdapter.resource(source)], poll_interval_ms: 10)
    assert_receive {:readiness_requested, ^source}
    :ok = TestReadinessAdapter.reply(source, :preparing)
    assert_receive {:readiness_requested, ^source}
    :ok = TestReadinessAdapter.reply(source, :ready)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}
    refute_receive {:readiness_requested, ^source}
  end

  test "reconciliation cancels stale probes without stopping retained resources" do
    source = adapter("source")
    incoming = adapter("incoming")
    source_resource = TestReadinessAdapter.resource(source)
    incoming_resource = TestReadinessAdapter.resource(incoming)
    collector = collector([source_resource])
    assert_receive {:readiness_requested, ^source}

    assert {:ok, %{prepare: [^incoming_resource], remove: [^source_resource]}} =
             Collector.reconcile(collector, "next-attempt", [incoming_resource])

    assert_receive {:readiness_requested, ^incoming}
    :ok = TestReadinessAdapter.reply(source, :ready)
    assert %{status: :preparing, attempt_id: "next-attempt"} = Collector.snapshot(collector)
    :ok = TestReadinessAdapter.reply(incoming, :ready)

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :ready, attempt_id: "next-attempt"}}
  end

  test "the original absolute deadline cancels a blocked probe and cannot be extended by reconcile" do
    source = adapter("source")
    resource = TestReadinessAdapter.resource(source)
    collector = collector([resource], deadline_ms: System.monotonic_time(:millisecond) + 1_000)
    assert_receive {:readiness_requested, ^source}
    assert {:ok, _diff} = Collector.reconcile(collector, "same-budget", [resource])

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :failed, failure: :deadline_elapsed}},
                   2_000

    assert {:error, :deadline_elapsed} = Collector.reconcile(collector, "too-late", [resource])
    :ok = TestReadinessAdapter.reply(source, :ready)
    assert %{status: :failed} = Collector.snapshot(collector)
  end

  test "a resource with no adapter blocks without being silently skipped" do
    source = adapter("source")
    resource = %{TestReadinessAdapter.resource(source) | adapter: nil}
    collector = collector([resource])
    assert %{status: :failed, blockers: [%{status: :failed}]} = Collector.snapshot(collector)
    refute_receive {:readiness_requested, _}
  end

  test "late ready evidence cannot win a race with the absolute deadline" do
    now = System.monotonic_time(:millisecond)
    clock = start_supervised!({Agent, fn -> now end})
    source = adapter("source")
    resource = TestReadinessAdapter.resource(source)

    collector =
      collector([resource], deadline_ms: now + 5_000, clock: fn -> Agent.get(clock, & &1) end)

    assert_receive {:readiness_requested, ^source}
    Agent.update(clock, fn _ -> now + 5_000 end)
    :ok = TestReadinessAdapter.reply(source, :ready)

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :failed, failure: :deadline_elapsed}}

    refute_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}
  end

  test "a timed-out observation can recover without replacing the healthy resource" do
    source = adapter("source")
    resource = TestReadinessAdapter.resource(source)
    collector = collector([resource], probe_timeout_ms: 100)
    assert_receive {:readiness_probe_caller, ^source, probe}
    monitor = Process.monitor(probe)
    assert_receive {:DOWN, ^monitor, :process, ^probe, :killed}, 1_000
    assert %{status: :preparing} = Collector.snapshot(collector)

    assert :ok = Collector.refresh(collector)
    assert_receive {:readiness_requested, ^source}
    assert_receive {:readiness_probe_caller, ^source, replacement_probe}
    assert replacement_probe != probe
    :ok = TestReadinessAdapter.reply(source, :ready)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}
    assert TestReadinessAdapter.resource(source) == resource
  end

  test "owner loss stops the collector and its outstanding probe" do
    owner =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :finish -> :ok
           end
         end}
      )

    source = adapter("source")
    collector = collector([TestReadinessAdapter.resource(source)], owner: owner)
    assert_receive {:readiness_probe_caller, ^source, probe}
    collector_monitor = Process.monitor(collector)
    probe_monitor = Process.monitor(probe)
    send(owner, :finish)
    assert_receive {:DOWN, ^collector_monitor, :process, ^collector, :normal}
    assert_receive {:DOWN, ^probe_monitor, :process, ^probe, _reason}
    assert %{} = TestReadinessAdapter.resource(source)
  end

  test "bounds concurrent probes and rejects an adapter that cannot report readiness" do
    first = adapter("first")
    second = adapter("second")
    resources = Enum.map([first, second], &TestReadinessAdapter.resource/1)
    collector = collector(resources, maximum_concurrency: 1)
    assert_receive {:readiness_requested, active}
    refute_receive {:readiness_requested, _}
    :ok = TestReadinessAdapter.reply(active, :ready)
    assert_receive {:readiness_requested, next}
    assert next != active
    :ok = TestReadinessAdapter.reply(next, :ready)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}

    unsupported = %{TestReadinessAdapter.resource(first) | adapter: String}
    assert {:ok, _diff} = Collector.reconcile(collector, "unsupported", [unsupported])
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}
  end

  defp adapter(id) do
    start_supervised!(
      Supervisor.child_spec({TestReadinessAdapter, id: id, observer: self()},
        id: {TestReadinessAdapter, id}
      )
    )
  end

  defp collector(resources, options \\ []) do
    incarnation = "readiness-#{System.unique_integer([:positive])}"
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: incarnation})

    assert {:ok, collector} =
             RoomCapabilitySupervisor.start_readiness(
               incarnation,
               Keyword.merge(
                 [
                   owner: self(),
                   attempt_id: "attempt",
                   resources: resources,
                   deadline_ms: System.monotonic_time(:millisecond) + 5_000,
                   poll_interval_ms: :manual
                 ],
                 options
               )
             )

    collector
  end
end
