defmodule Vxpipe.CallEngine.MediaPolicy.AuthorityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition.{TransferPolicy, VariablePermissions}
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

  test "candidate validation fences the authority, live policy and recomputed result" do
    definition = plan(%{"caller" => MediaPolicy.inherit(), "joining" => MediaPolicy.inherit()})
    server = start_authority(definition)
    other = start_authority(definition)
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

  defp plan(presence_policies) do
    participants =
      Map.new(presence_policies, fn {participant_id, presence_policy} ->
        {participant_id, participant(participant_id, presence_policy)}
      end)

    %ResolvedCallPlan{
      definition_id: "definition-policy-authority",
      definition_revision: 1,
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
      definition_key: participant_id,
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
