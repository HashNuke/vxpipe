defmodule Vxpipe.CallEngine.MediaPolicy.AuthorityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.{TransferPolicy, VariablePermissions}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Effective, Snapshot}
  alias Vxpipe.CallEngine.TestMediaPolicyEnforcer

  alias Vxpipe.CallEngine.ResolvedCallPlan

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    CallVariables,
    Capabilities,
    MediaPolicy,
    Participant,
    ToolVisibility
  }

  test "starts from the host ceiling and normal call policy with no presence contributions" do
    plan = plan(%{"specialist-id" => MediaPolicy.inherit()})

    server = start_authority(plan)

    assert %Snapshot{
             revision: 0,
             present_participant_ids: present,
             effective: %Effective{record_audio: true, save_transcripts: true}
           } = Authority.snapshot(server)

    assert present == MapSet.new()
  end

  test "admits only pinned participants and applies their presence restriction atomically" do
    restriction =
      policy(
        audio_routes: %{
          "caller-id" => ["specialist-id"],
          "specialist-id" => ["caller-id"]
        },
        record_audio: false
      )

    plan = plan(%{"specialist-id" => restriction})
    server = start_authority(plan)

    assert {:ok,
            %Snapshot{
              revision: 1,
              present_participant_ids: present,
              effective: effective
            }} = Authority.admit(server, "specialist-id")

    assert present == MapSet.new(["specialist-id"])
    refute effective.record_audio
    assert effective.save_transcripts

    assert effective.audio_routes == %{
             "caller-id" => MapSet.new(["specialist-id"]),
             "specialist-id" => MapSet.new(["caller-id"])
           }

    assert {:error, :already_present} = Authority.admit(server, "specialist-id")
    assert {:error, :unknown_participant} = Authority.admit(server, "unplanned-id")
    assert Authority.snapshot(server).revision == 1
  end

  test "leave removes only that participant's contribution and advances the revision" do
    plan =
      plan(%{
        "specialist-id" => policy(record_audio: false),
        "observer-id" => policy(save_transcripts: false)
      })

    server = start_authority(plan)

    assert {:ok, %Snapshot{revision: 1}} = Authority.admit(server, "specialist-id")
    assert {:ok, %Snapshot{revision: 2}} = Authority.admit(server, "observer-id")

    assert {:ok,
            %Snapshot{
              revision: 3,
              present_participant_ids: present,
              effective: effective
            }} = Authority.leave(server, "specialist-id")

    assert present == MapSet.new(["observer-id"])
    assert effective.record_audio
    refute effective.save_transcripts
    assert {:error, :not_present} = Authority.leave(server, "specialist-id")
    assert Authority.snapshot(server).revision == 3
  end

  test "refuses startup when the host ceiling is malformed" do
    Process.flag(:trap_exit, true)
    malformed_ceiling = %{MediaPolicy.inherit() | record_audio: :enabled}

    assert {:error, :invalid_policy} =
             Authority.start_link(
               plan: plan(%{}),
               incarnation_id: "incarnation-invalid-policy",
               register: false,
               media_policy_ceiling: malformed_ceiling
             )
  end

  test "previews the complete resulting membership without changing live privacy or enforcers" do
    audience = ["listener-1", "listener-2", "listener-3", "listener-4"]

    policies =
      Map.new(audience ++ ["joining", "unused"], &{&1, MediaPolicy.inherit()})
      |> Map.put("departing", policy(record_audio: false, save_transcripts: false))

    server = start_authority(plan(policies))

    for participant <- audience ++ ["departing"] do
      assert {:ok, _snapshot} = Authority.admit(server, participant)
    end

    current = Authority.snapshot(server)
    enforcer = start_enforcer()
    assert {:ok, ^current} = Authority.register_enforcer(server, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, ^current}
    resulting_presence = MapSet.new(audience ++ ["joining"])

    assert {:ok, candidate} = Authority.preview_presence(server, resulting_presence)
    assert candidate.base_snapshot == current
    assert candidate.snapshot.revision == current.revision + 1
    assert candidate.snapshot.present_participant_ids == resulting_presence
    assert candidate.snapshot.effective.record_audio
    assert candidate.snapshot.effective.save_transcripts

    for listener <- audience do
      assert Snapshot.interval(candidate.snapshot, :audio_output, listener) ==
               Snapshot.interval(current, :audio_output, listener)

      assert Snapshot.interval(candidate.snapshot, :speech_to_text, listener) ==
               candidate.snapshot.revision
    end

    assert Snapshot.interval(candidate.snapshot, :audio_input, "joining") ==
             candidate.snapshot.revision

    assert :ok = Authority.validate_candidate(server, candidate)
    assert {:ok, ^candidate} = Authority.preview_presence(server, resulting_presence)
    assert Authority.snapshot(server) == current
    refute current.effective.record_audio
    refute_receive {:media_policy_applied, ^enforcer, _candidate}
  end

  test "commits the complete prepared membership in one revision and awaits policy acknowledgement" do
    audience = ["one", "two", "three", "four"]
    policies = Map.new(audience ++ ["departing", "joining"], &{&1, MediaPolicy.inherit()})
    server = start_authority(plan(policies))

    for participant <- audience ++ ["departing"] do
      assert {:ok, _} = Authority.admit(server, participant)
    end

    current = Authority.snapshot(server)
    enforcer = start_enforcer()
    assert {:ok, ^current} = Authority.register_enforcer(server, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, ^current}
    :sys.replace_state(enforcer, &Map.put(&1, :mode, :manual))

    assert {:ok, candidate} =
             Authority.preview_presence(server, MapSet.new(audience ++ ["joining"]))

    expected = candidate.snapshot
    deadline = System.monotonic_time(:millisecond) + 5_000
    task = Task.async(fn -> Authority.commit_candidate(server, candidate, deadline) end)
    assert_receive {:media_policy_applied, ^enforcer, ^expected}
    assert Task.yield(task, 0) == nil
    TestMediaPolicyEnforcer.acknowledge(enforcer, :ok)
    assert {:ok, ^expected} = Task.await(task)
    assert expected.revision == current.revision + 1
    assert Authority.snapshot(server) == expected
    refute_receive {:media_policy_applied, ^enforcer, _intermediate}
    assert {:error, :not_present} = Authority.leave(server, "departing")
    assert {:error, :already_present} = Authority.admit(server, "joining")
  end

  test "candidate commit rejects expired, forged, foreign and stale evidence without applying policy" do
    call_spec = plan(%{"caller" => MediaPolicy.inherit(), "joining" => MediaPolicy.inherit()})
    server = start_authority(call_spec)
    foreign = start_authority(call_spec)
    assert {:ok, current} = Authority.admit(server, "caller")
    enforcer = start_enforcer()
    assert {:ok, ^current} = Authority.register_enforcer(server, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, ^current}

    assert {:ok, candidate} =
             Authority.preview_presence(server, MapSet.new(["caller", "joining"]))

    deadline = System.monotonic_time(:millisecond) + 5_000
    changed = %{candidate.snapshot.effective | record_audio: false}
    forged = %{candidate | snapshot: %{candidate.snapshot | effective: changed}}

    assert {:error, :deadline_elapsed} =
             Authority.commit_candidate(server, candidate, deadline - 5_001)

    assert {:error, :invalid_deadline} = Authority.commit_candidate(server, candidate, nil)
    assert {:error, :invalid_candidate} = Authority.commit_candidate(server, forged, deadline)
    assert {:error, :invalid_candidate} = Authority.commit_candidate(foreign, candidate, deadline)
    assert Authority.snapshot(server) == current
    refute_receive {:media_policy_applied, ^enforcer, _snapshot}
    assert {:ok, installed} = Authority.admit(server, "joining")
    assert_receive {:media_policy_applied, ^enforcer, ^installed}
    assert {:error, :stale_candidate} = Authority.commit_candidate(server, candidate, deadline)
    refute_receive {:media_policy_applied, ^enforcer, _snapshot}
  end

  test "candidate commit adopts private enforcers once and waits before making them critical" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    current = Authority.snapshot(server)
    existing = start_enforcer()
    joining = start_enforcer(mode: :manual)
    assert {:ok, ^current} = Authority.register_enforcer(server, existing)
    assert_receive {:media_policy_applied, ^existing, ^current}
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new(["joining"]))
    expected = candidate.snapshot
    deadline = System.monotonic_time(:millisecond) + 5_000

    task =
      Task.async(fn ->
        Authority.commit_candidate(server, candidate, deadline, [joining, existing, joining])
      end)

    assert_receive {:media_policy_applied, ^joining, ^expected}
    assert Task.yield(task, 0) == nil
    TestMediaPolicyEnforcer.acknowledge(joining, :ok)
    assert {:ok, ^expected} = Task.await(task)
    assert_receive {:media_policy_applied, ^existing, ^expected}
    refute_receive {:media_policy_applied, _, _}
    assert {:error, :already_registered} = Authority.register_enforcer(server, joining)

    monitor = Process.monitor(server)
    Process.exit(joining, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^server,
                    {:media_policy_enforcer_unavailable, ^joining, :killed}},
                   1_000
  end

  test "rejected candidate adoption never registers or changes a private enforcer" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    current = Authority.snapshot(server)
    joining = start_enforcer()
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new(["joining"]))
    deadline = System.monotonic_time(:millisecond) + 5_000

    assert {:error, :invalid_enforcers} =
             Authority.commit_candidate(server, candidate, deadline, [joining, nil])

    assert {:error, :invalid_enforcers} =
             Authority.commit_candidate(server, candidate, deadline, %{joining: joining})

    assert {:error, :deadline_elapsed} =
             Authority.commit_candidate(server, candidate, deadline - 5_001, [joining])

    assert {:error, :invalid_candidate} =
             Authority.commit_candidate(server, nil, deadline, [joining])

    assert Authority.snapshot(server) == current
    refute_receive {:media_policy_applied, ^joining, _}
    monitor = Process.monitor(joining)
    Process.exit(joining, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^joining, :killed}
    assert Authority.snapshot(server) == current
  end

  test "a private enforcer refusing the candidate fails the commit closed" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    joining = start_enforcer(mode: {:error, :policy_not_ready})
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new(["joining"]))
    monitor = Process.monitor(server)

    assert {:error, :enforcement_failed} =
             Authority.commit_candidate(
               server,
               candidate,
               System.monotonic_time(:millisecond) + 5_000,
               [joining]
             )

    assert_receive {:DOWN, ^monitor, :process, ^server, :media_policy_enforcement_failed}
  end

  test "unchanged candidate preserves installed enforcers and rejects new adoption before application" do
    server = start_authority(plan(%{"caller" => MediaPolicy.inherit()}))
    assert {:ok, current} = Authority.admit(server, "caller")
    existing = start_enforcer()
    joining = start_enforcer()
    assert {:ok, ^current} = Authority.register_enforcer(server, existing)
    assert_receive {:media_policy_applied, ^existing, ^current}
    assert {:ok, candidate} = Authority.preview_presence(server, current.present_participant_ids)
    deadline = System.monotonic_time(:millisecond) + 5_000

    assert {:ok, ^current} = Authority.commit_candidate(server, candidate, deadline)
    refute_receive {:media_policy_applied, _, _}

    assert {:ok, ^current} =
             Authority.commit_candidate(server, candidate, deadline, [existing, existing])

    assert {:error, :unchanged_candidate} =
             Authority.commit_candidate(server, candidate, deadline, [joining])

    assert {:error, :deadline_elapsed} =
             Authority.commit_candidate(server, candidate, deadline - 5_001)

    refute_receive {:media_policy_applied, _, _}
    assert Authority.snapshot(server) == current
    assert {:ok, ^current} = Authority.register_enforcer(server, joining)
  end

  test "candidate commit fails closed when acknowledgement exceeds the remaining attempt budget" do
    server =
      start_authority(plan(%{"caller" => MediaPolicy.inherit()}), enforcement_timeout_ms: 5_000)

    enforcer = start_enforcer()
    current = Authority.snapshot(server)
    assert {:ok, ^current} = Authority.register_enforcer(server, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, ^current}
    :sys.replace_state(enforcer, &Map.put(&1, :mode, :manual))
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new(["caller"]))
    monitor = Process.monitor(server)
    deadline = System.monotonic_time(:millisecond) + 1_000
    task = Task.async(fn -> Authority.commit_candidate(server, candidate, deadline) end)
    assert_receive {:media_policy_applied, ^enforcer, _snapshot}, 1_000
    assert {:error, :enforcement_failed} = Task.await(task, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^server, :media_policy_enforcement_failed}
  end

  test "candidate validation fences the authority, live policy and recomputed result" do
    call_spec = plan(%{"caller" => MediaPolicy.inherit(), "joining" => MediaPolicy.inherit()})
    server = start_authority(call_spec)
    other = start_authority(call_spec)
    assert {:ok, current} = Authority.admit(server, "caller")

    assert {:ok, candidate} =
             Authority.preview_presence(server, MapSet.new(["caller", "joining"]))

    assert {:error, :invalid_candidate} = Authority.validate_candidate(other, candidate)
    changed_policy = %{candidate.snapshot.effective | record_audio: false}
    forged = %{candidate | snapshot: %{candidate.snapshot | effective: changed_policy}}
    assert {:error, :invalid_candidate} = Authority.validate_candidate(server, forged)
    assert {:error, :invalid_candidate} = Authority.validate_candidate(server, nil)
    assert Authority.snapshot(server) == current

    assert {:ok, _snapshot} = Authority.admit(server, "joining")
    assert {:error, :stale_candidate} = Authority.validate_candidate(server, candidate)
  end

  test "preview retains the host ceiling and rejects unknown or malformed membership" do
    server =
      start_authority(
        plan(%{"caller" => MediaPolicy.inherit()}),
        media_policy_ceiling: policy(record_audio: false)
      )

    current = Authority.snapshot(server)
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new(["caller"]))
    refute candidate.snapshot.effective.record_audio

    assert {:error, :unknown_participant} =
             Authority.preview_presence(server, MapSet.new(["unplanned"]))

    assert {:error, :invalid_presence} = Authority.preview_presence(server, ["caller"])
    assert {:error, :invalid_presence} = Authority.preview_presence(server, MapSet.new([nil]))
    assert Authority.snapshot(server) == current
  end

  test "unchanged prospective membership retains the exact installed snapshot" do
    server = start_authority(plan(%{"caller" => MediaPolicy.inherit()}))
    assert {:ok, current} = Authority.admit(server, "caller")

    assert {:ok, candidate} =
             Authority.preview_presence(server, current.present_participant_ids)

    assert candidate.snapshot == current
    assert :ok = Authority.validate_candidate(server, candidate)
  end

  test "a preview and the corresponding live transition compute identical permission intervals" do
    server = start_authority(plan(%{"caller" => policy(record_audio: false)}))
    assert {:ok, _current} = Authority.admit(server, "caller")
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new())
    assert {:ok, installed} = Authority.leave(server, "caller")
    assert candidate.snapshot == installed
  end

  test "refuses startup with a non-positive enforcement timeout" do
    Process.flag(:trap_exit, true)

    assert {:error, :invalid_policy_enforcement_timeout} =
             Authority.start_link(
               plan: plan(%{}),
               incarnation_id: "incarnation-invalid-enforcement-timeout",
               register: false,
               media_policy_enforcement_timeout_ms: 0
             )
  end

  test "registers an enforcer only after it installs the current revision" do
    server = start_authority(plan(%{}))
    enforcer = start_enforcer()

    assert {:ok, %Snapshot{revision: 0}} = Authority.register_enforcer(server, enforcer)

    assert_receive {:media_policy_applied, ^enforcer, %Snapshot{revision: 0}}
    assert {:error, :already_registered} = Authority.register_enforcer(server, enforcer)
  end

  test "does not acknowledge admission until every enforcer installs the new revision" do
    server = start_authority(plan(%{"specialist-id" => policy(record_audio: false)}))
    automatic = start_enforcer()
    manual = start_enforcer(mode: :manual)

    assert {:ok, %Snapshot{revision: 0}} = Authority.register_enforcer(server, automatic)
    assert_receive {:media_policy_applied, ^automatic, %Snapshot{revision: 0}}

    registration = Task.async(fn -> Authority.register_enforcer(server, manual) end)
    assert_receive {:media_policy_applied, ^manual, %Snapshot{revision: 0}}
    assert Task.yield(registration, 0) == nil
    TestMediaPolicyEnforcer.acknowledge(manual, :ok)
    assert {:ok, %Snapshot{revision: 0}} = Task.await(registration)

    admission = Task.async(fn -> Authority.admit(server, "specialist-id") end)

    assert_receive {:media_policy_applied, ^automatic, %Snapshot{revision: 1}}
    assert_receive {:media_policy_applied, ^manual, %Snapshot{revision: 1}}
    assert Task.yield(admission, 0) == nil

    TestMediaPolicyEnforcer.acknowledge(manual, :ok)

    assert {:ok, %Snapshot{revision: 1, effective: %Effective{record_audio: false}}} =
             Task.await(admission)
  end

  test "fails closed when an enforcer rejects a transition" do
    Process.flag(:trap_exit, true)
    server = start_authority(plan(%{"specialist-id" => policy(record_audio: false)}))
    enforcer = start_enforcer(mode: :ok)

    assert {:ok, %Snapshot{revision: 0}} = Authority.register_enforcer(server, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, %Snapshot{revision: 0}}

    :sys.replace_state(enforcer, &Map.put(&1, :mode, {:error, :cannot_apply}))
    monitor = Process.monitor(server)

    assert {:error, :enforcement_failed} = Authority.admit(server, "specialist-id")
    assert_receive {:DOWN, ^monitor, :process, ^server, :media_policy_enforcement_failed}
  end

  test "fails closed when a registered enforcer exits" do
    Process.flag(:trap_exit, true)
    server = start_authority(plan(%{}))
    enforcer = start_enforcer()

    assert {:ok, %Snapshot{revision: 0}} = Authority.register_enforcer(server, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, %Snapshot{revision: 0}}

    monitor = Process.monitor(server)
    Process.exit(enforcer, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^server,
                    {:media_policy_enforcer_unavailable, ^enforcer, :killed}},
                   1_000
  end

  test "retires only a departed connection's enforcers before the next policy revision" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    connection = start_enforcer()
    departed = start_enforcer()
    retained = start_enforcer()

    assert {:ok, _} = Authority.register_connection_enforcer(server, departed, connection)
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert_receive {:media_policy_applied, ^departed, _}
    assert_receive {:media_policy_applied, ^retained, _}

    :ok = :sys.suspend(server)
    monitor = Process.monitor(connection)
    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :killed}
    monitor = Process.monitor(departed)
    Process.exit(departed, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^departed, :killed}
    :ok = :sys.resume(server)

    assert {:ok, snapshot} = Authority.admit(server, "joining")
    assert_receive {:media_policy_applied, ^retained, ^snapshot}
    assert Authority.snapshot(server) == snapshot
  end

  test "a connection enforcer remains critical while its connection is alive" do
    server = start_authority(plan(%{}))
    enforcer = start_enforcer()
    assert {:ok, _} = Authority.register_connection_enforcer(server, enforcer, self())
    monitor = Process.monitor(server)
    Process.exit(enforcer, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^server,
                    {:media_policy_enforcer_unavailable, ^enforcer, :killed}}
  end

  test "explicit retirement removes a live connection's enforcers before teardown" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    first = start_enforcer()
    second = start_enforcer()
    retained = start_enforcer()

    assert {:ok, _} = Authority.register_connection_enforcer(server, first, self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, second, self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert_receive {:media_policy_applied, ^first, _}
    assert_receive {:media_policy_applied, ^second, _}
    assert_receive {:media_policy_applied, ^retained, _}

    assert :ok = Authority.retire_connection_enforcers(server, self(), [first, second])
    first_monitor = Process.monitor(first)
    second_monitor = Process.monitor(second)
    Process.exit(first, :kill)
    Process.exit(second, :kill)
    assert_receive {:DOWN, ^first_monitor, :process, ^first, :killed}
    assert_receive {:DOWN, ^second_monitor, :process, ^second, :killed}

    assert {:ok, snapshot} = Authority.admit(server, "joining")
    assert_receive {:media_policy_applied, ^retained, ^snapshot}
    assert Authority.snapshot(server) == snapshot
  end

  test "a failed connection enforcer group stops locally and retains other connection media" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    failed = start_enforcer()
    grouped = start_enforcer(trap_exit: true)
    retained = start_enforcer()

    assert {:ok, _} = Authority.register_connection_enforcers(server, [failed, grouped], self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert_receive {:media_policy_applied, ^failed, _}
    assert_receive {:media_policy_applied, ^grouped, _}
    assert_receive {:media_policy_applied, ^retained, _}

    grouped_monitor = Process.monitor(grouped)
    Process.exit(failed, :kill)
    assert_receive {:DOWN, ^grouped_monitor, :process, ^grouped, :killed}

    assert {:ok, snapshot} = Authority.admit(server, "joining")
    assert_receive {:media_policy_applied, ^retained, ^snapshot}
    assert Authority.snapshot(server) == snapshot
  end

  test "a group that rejects initial policy is killed without stopping the authority" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    rejecting = start_enforcer(mode: {:error, :rejected})
    grouped = start_enforcer(trap_exit: true)
    rejecting_monitor = Process.monitor(rejecting)
    grouped_monitor = Process.monitor(grouped)

    assert {:error, :enforcement_failed} =
             Authority.register_connection_enforcers(server, [rejecting, grouped], self())

    assert_receive {:DOWN, ^rejecting_monitor, :process, ^rejecting, :killed}
    assert_receive {:DOWN, ^grouped_monitor, :process, ^grouped, :killed}
    assert {:ok, snapshot} = Authority.admit(server, "joining")
    assert Authority.snapshot(server) == snapshot
  end

  test "a queued policy transition retires a group whose failure signal is still queued" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    failed = start_enforcer()
    grouped = start_enforcer()
    retained = start_enforcer()

    assert {:ok, _} = Authority.register_connection_enforcers(server, [failed, grouped], self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert_receive {:media_policy_applied, ^failed, _}
    assert_receive {:media_policy_applied, ^grouped, _}
    assert_receive {:media_policy_applied, ^retained, _}

    :ok = :sys.suspend(server)
    failed_monitor = Process.monitor(failed)
    grouped_monitor = Process.monitor(grouped)
    tag = make_ref()

    TestMediaPolicyEnforcer.request_and_stop(
      failed,
      server,
      {:admit, "joining"},
      self(),
      tag
    )

    assert_receive {:DOWN, ^failed_monitor, :process, ^failed, :normal}
    :ok = :sys.resume(server)

    assert_receive {^tag, {:ok, snapshot}}, 1_000
    assert_receive {:DOWN, ^grouped_monitor, :process, ^grouped, :killed}
    assert_receive {:media_policy_applied, ^retained, ^snapshot}
    assert Authority.snapshot(server) == snapshot
  end

  test "a grouped failure during enforcement continues without replaying accepted revisions" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    enforcers = Enum.map(1..4, fn _index -> start_enforcer() end)
    [retained, held, grouped, survivor] = policy_order(enforcers)

    assert {:ok, _} = Authority.register_connection_enforcers(server, [held, grouped], self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, survivor, self())
    assert_receive {:media_policy_applied, ^held, _}
    assert_receive {:media_policy_applied, ^grouped, _}
    assert_receive {:media_policy_applied, ^retained, _}
    assert_receive {:media_policy_applied, ^survivor, _}
    :sys.replace_state(retained, &Map.put(&1, :mode, :monotonic))
    :sys.replace_state(held, &Map.put(&1, :mode, :manual))
    :sys.replace_state(survivor, &Map.put(&1, :mode, :monotonic))

    grouped_monitor = Process.monitor(grouped)
    admission = Task.async(fn -> Authority.admit(server, "joining") end)
    assert_receive {:media_policy_applied, ^retained, snapshot}
    assert_receive {:media_policy_applied, ^held, ^snapshot}
    refute_received {:media_policy_applied, ^grouped, ^snapshot}
    refute_received {:media_policy_applied, ^survivor, ^snapshot}
    Process.exit(held, :kill)

    assert {:ok, ^snapshot} = Task.await(admission)
    assert_receive {:DOWN, ^grouped_monitor, :process, ^grouped, :killed}
    assert_receive {:media_policy_applied, ^survivor, ^snapshot}
    refute_receive {:media_policy_applied, ^retained, ^snapshot}
    assert Authority.snapshot(server) == snapshot
  end

  test "retiring one grouped enforcer retires the whole registration without killing peers" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    first = start_enforcer()
    second = start_enforcer()
    retained = start_enforcer()

    assert {:ok, _} = Authority.register_connection_enforcers(server, [first, second], self())
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert_receive {:media_policy_applied, ^first, _}
    assert_receive {:media_policy_applied, ^second, _}
    assert_receive {:media_policy_applied, ^retained, _}

    second_monitor = Process.monitor(second)
    assert :ok = Authority.retire_connection_enforcers(server, self(), [first])
    Process.exit(first, :kill)

    assert {:ok, snapshot} = Authority.admit(server, "joining")
    assert_receive {:media_policy_applied, ^retained, ^snapshot}
    refute_receive {:media_policy_applied, ^second, ^snapshot}
    refute_receive {:DOWN, ^second_monitor, :process, ^second, _reason}
    assert Authority.snapshot(server) == snapshot
  end

  test "candidate adoption retains the destination connection's enforcer lifetime" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    connection = start_enforcer()
    enforcer = start_enforcer()
    assert {:ok, candidate} = Authority.preview_presence(server, MapSet.new(["joining"]))

    assert {:ok, _} =
             Authority.commit_candidate(
               server,
               candidate,
               System.monotonic_time(:millisecond) + 5_000,
               [{enforcer, connection}]
             )

    assert_receive {:media_policy_applied, ^enforcer, _}
    monitor = Process.monitor(connection)
    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :killed}
    _ = :sys.get_state(server)
    monitor = Process.monitor(enforcer)
    Process.exit(enforcer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^enforcer, :killed}
    assert {:ok, _} = Authority.leave(server, "joining")
  end

  test "a departure during enforcement does not abort policy application to surviving connections" do
    server = start_authority(plan(%{"joining" => MediaPolicy.inherit()}))
    connection = start_enforcer()
    departed = start_enforcer()
    retained = start_enforcer()
    assert {:ok, _} = Authority.register_connection_enforcer(server, departed, connection)
    assert {:ok, _} = Authority.register_connection_enforcer(server, retained, self())
    assert_receive {:media_policy_applied, ^departed, _}
    assert_receive {:media_policy_applied, ^retained, _}
    :sys.replace_state(departed, &Map.put(&1, :mode, :manual))

    admission = Task.async(fn -> Authority.admit(server, "joining") end)
    assert_receive {:media_policy_applied, ^departed, snapshot}
    monitor = Process.monitor(connection)
    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :killed}
    monitor = Process.monitor(departed)
    Process.exit(departed, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^departed, :killed}

    assert {:ok, ^snapshot} = Task.await(admission)
    assert_receive {:media_policy_applied, ^retained, ^snapshot}
    assert Authority.snapshot(server) == snapshot
  end

  defp start_authority(plan, overrides \\ []) do
    options = [
      plan: plan,
      incarnation_id: "incarnation-#{System.unique_integer([:positive])}",
      register: false,
      media_policy_ceiling: MediaPolicy.inherit()
    ]

    options
    |> Keyword.merge(overrides)
    |> Authority.child_spec()
    |> Map.put(:significant, false)
    |> start_supervised!()
  end

  defp start_enforcer(options \\ []) do
    start_supervised!(
      {TestMediaPolicyEnforcer, Keyword.merge([owner: self(), mode: :ok], options)}
    )
  end

  defp policy_order(enforcers) do
    enforcers
    |> Map.new(&{&1, nil})
    |> Enum.map(fn {enforcer, nil} -> enforcer end)
  end

  defp plan(presence_policies) do
    participants =
      Map.new(presence_policies, fn {participant_id, presence_policy} ->
        {participant_id, participant(participant_id, presence_policy)}
      end)

    %ResolvedCallPlan{
      call_spec_id: "call-spec-policy-authority",
      call_spec_revision: 1,
      schema_version: "20260913.01",
      tenant_id: "tenant-policy",
      actor_id: "actor-policy",
      call_id: "call-policy",
      room_id: "room-policy",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "receiver",
      opening_audio: nil,
      media_policy: MediaPolicy.inherit(),
      participants: participants,
      transfer_policy: %TransferPolicy{attempt_timeout_ms: 30_000},
      call_variables: %CallVariables{},
      tool_visibility: ToolVisibility.hidden(),
      max_duration_ms: 60_000
    }
  end

  defp participant(participant_id, presence_policy) do
    %Participant{
      call_spec_key: participant_id,
      participant_id: participant_id,
      activation_id: nil,
      kind: :human,
      description: nil,
      connection: nil,
      transfer_notice: nil,
      prompt: nil,
      first_message: nil,
      first_message_text: nil,
      capabilities: %Capabilities{},
      while_present: presence_policy,
      tools: %{},
      transfers: [],
      transfer_history: nil,
      variable_permissions: %VariablePermissions{}
    }
  end

  defp policy(overrides) do
    Enum.reduce(overrides, MediaPolicy.inherit(), fn
      {field, routes}, policy when field in [:audio_routes, :transcript_routes] ->
        Map.put(
          policy,
          field,
          Map.new(routes, fn {source, recipients} -> {source, MapSet.new(recipients)} end)
        )

      {field, value}, policy ->
        Map.put(policy, field, value)
    end)
  end
end
