defmodule Vxpipe.CallEngine.Readiness.BarrierTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Readiness.{Barrier, Report, Resource}

  test "waits for every participant and room resource, not just a running destination STT" do
    caller = resource(:speech_to_text, {:participant, "caller"})
    destination = resource(:speech_to_text, {:participant, "support"})
    mixer = resource(:room_mixer, :room)
    barrier = Barrier.new("room-incarnation", "transfer-attempt", [caller, destination, mixer])

    assert Barrier.status(barrier) == :preparing
    barrier = acknowledge(barrier, destination)
    assert Barrier.status(barrier) == :preparing
    barrier = acknowledge(barrier, caller)
    assert Barrier.status(barrier) == :preparing
    assert Barrier.blockers(barrier) == [%{kind: :room_mixer, scope: :room, status: :preparing}]
    assert Barrier.status(acknowledge(barrier, mixer)) == :ready
  end

  test "refuses foreign rooms, attempts, instances, configurations and policy intervals" do
    stt = resource(:speech_to_text, {:participant, "support"})
    barrier = Barrier.new("room-incarnation", "transfer-attempt", [stt])
    report = report(barrier, stt, :ready)

    invalid = [
      %{report | incarnation_id: "another-incarnation"},
      %{report | attempt_id: "another-attempt"},
      %{report | request_id: make_ref()},
      %{report | resource: %{stt | generation: make_ref()}},
      %{report | resource: %{stt | configuration: Resource.signature(:another_voice)}},
      %{report | resource: %{stt | policy_interval: 2}},
      %{report | resource: %{stt | instance: nil}}
    ]

    for stale <- invalid do
      assert {:ignored, ^barrier} = Barrier.report(barrier, stale)
    end

    assert {:accepted, ready} = Barrier.report(barrier, report)
    assert Barrier.status(ready) == :ready
  end

  test "reconciliation retains unchanged readiness and prepares only added or changed bindings" do
    caller = resource(:speech_to_text, {:participant, "caller"})
    source = resource(:model_inference, {:participant, "source-agent"})
    mixer = resource(:room_mixer, :room)
    barrier = Barrier.new("room-incarnation", "startup", [caller, source, mixer])
    ready = Enum.reduce([caller, source, mixer], barrier, &acknowledge(&2, &1))
    incoming = resource(:model_inference, {:participant, "incoming-agent"})

    {handoff, diff} = Barrier.reconcile(ready, "handoff", [caller, incoming, mixer])
    assert diff.prepare == [incoming]
    assert diff.remove == [source]
    assert MapSet.new(diff.retain) == MapSet.new([caller, mixer])

    assert Barrier.blockers(handoff) == [
             %{
               kind: :model_inference,
               scope: {:participant, "incoming-agent"},
               status: :preparing
             }
           ]

    assert {:ignored, ^handoff} = Barrier.report(handoff, report(barrier, caller, :ready))
    handoff = acknowledge(handoff, incoming)
    assert Barrier.status(handoff) == :ready

    changed = %{caller | policy_interval: 1, generation: make_ref()}
    {revised, diff} = Barrier.reconcile(handoff, "handoff", [changed, incoming, mixer])
    assert diff.prepare == [changed]
    assert diff.remove == [caller]
    assert MapSet.new(diff.retain) == MapSet.new([incoming, mixer])
    assert Barrier.status(revised) == :preparing
  end

  test "a new attempt or a removed and restored binding cannot accept an old pending reply" do
    caller = resource(:speech_to_text, {:participant, "caller"})
    first = Barrier.new("room-incarnation", "first", [caller])
    old_report = report(first, caller, :ready)
    {second, _diff} = Barrier.reconcile(first, "second", [caller])
    assert {:ignored, ^second} = Barrier.report(second, old_report)
    new_report = report(second, caller, :ready)
    {empty, _diff} = Barrier.reconcile(second, "second", [])
    {restored, _diff} = Barrier.reconcile(empty, "second", [caller])
    assert {:ignored, ^restored} = Barrier.report(restored, new_report)
    assert Barrier.status(acknowledge(restored, caller)) == :ready
  end

  test "missing and unsupported required bindings never count as ready" do
    missing = %{resource(:speech_to_text, {:participant, "support"}) | instance: nil}
    unsupported = %{resource(:unknown_capability, :room) | adapter: nil}
    barrier = Barrier.new("room-incarnation", "attempt", [missing, unsupported])
    assert Barrier.status(barrier) == :failed

    assert Barrier.blockers(barrier) == [
             %{kind: :speech_to_text, scope: {:participant, "support"}, status: :preparing},
             %{kind: :unknown_capability, scope: :room, status: :failed}
           ]

    assert {:ignored, ^barrier} = Barrier.report(barrier, report(barrier, missing, :ready))
    assert {:ignored, ^barrier} = Barrier.report(barrier, report(barrier, unsupported, :ready))
  end

  test "readiness loss closes the barrier and a failed generation cannot be revived" do
    stt = resource(:speech_to_text, {:participant, "support"})
    barrier = Barrier.new("room-incarnation", "attempt", [stt]) |> acknowledge(stt)
    assert {:accepted, preparing} = Barrier.report(barrier, report(barrier, stt, :preparing))
    assert Barrier.status(preparing) == :preparing
    barrier = acknowledge(preparing, stt)
    assert {:accepted, failed} = Barrier.report(barrier, report(barrier, stt, :failed))
    assert Barrier.status(failed) == :failed
    assert {:ignored, ^failed} = Barrier.report(failed, report(failed, stt, :ready))

    replacement = %{stt | generation: make_ref()}
    {recovering, _diff} = Barrier.reconcile(failed, "attempt", [replacement])
    assert Barrier.status(acknowledge(recovering, replacement)) == :ready
  end

  test "rejects duplicate required resource identities instead of silently dropping one" do
    resource = resource(:room_mixer, :room)

    assert_raise ArgumentError, ~r/duplicate readiness resource/, fn ->
      Barrier.new("room-incarnation", "attempt", [resource, resource])
    end
  end

  test "an older ready report cannot erase a later loss of readiness" do
    mixer = resource(:room_mixer, :room)
    barrier = Barrier.new("room-incarnation", "attempt", [mixer])
    ready = report(barrier, mixer, :ready)
    assert {:accepted, barrier} = Barrier.report(barrier, ready)
    assert {:accepted, barrier} = Barrier.report(barrier, report(barrier, mixer, :preparing))
    assert {:ignored, ^barrier} = Barrier.report(barrier, ready)
    assert Barrier.status(barrier) == :preparing
  end

  test "requires each connection binding when a participant has more than one" do
    first = Map.put(resource(:speech_to_text, {:participant, "caller"}), :binding, "phone")
    second = %{first | binding: "browser", generation: make_ref()}
    barrier = Barrier.new("room-incarnation", "attempt", [first, second])
    barrier = acknowledge(barrier, first)
    assert Barrier.status(barrier) == :preparing
    assert Barrier.status(acknowledge(barrier, second)) == :ready
  end

  defp resource(kind, scope) do
    struct!(Resource,
      kind: kind,
      scope: scope,
      instance: self(),
      generation: make_ref(),
      configuration: Resource.signature({kind, scope, :configured}),
      policy_interval: 0,
      adapter: __MODULE__
    )
  end

  defp acknowledge(barrier, resource) do
    assert {:accepted, updated} = Barrier.report(barrier, report(barrier, resource, :ready))
    updated
  end

  defp report(barrier, resource, status) do
    struct!(Report,
      incarnation_id: barrier.incarnation_id,
      attempt_id: barrier.attempt_id,
      request_id: Barrier.request_id(barrier, Resource.key(resource)),
      resource: resource,
      sequence: System.unique_integer([:positive, :monotonic]),
      status: status
    )
  end
end
