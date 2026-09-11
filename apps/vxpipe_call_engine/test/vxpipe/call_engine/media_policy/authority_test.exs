defmodule Vxpipe.CallEngine.MediaPolicy.AuthorityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition.{TransferPolicy, VariablePermissions}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Effective, Snapshot}

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

  defp start_authority(plan) do
    options = [
      plan: plan,
      incarnation_id: "incarnation-#{System.unique_integer([:positive])}",
      register: false,
      media_policy_ceiling: MediaPolicy.inherit()
    ]

    options
    |> Authority.child_spec()
    |> Map.put(:significant, false)
    |> start_supervised!()
  end

  defp plan(presence_policies) do
    participants =
      Map.new(presence_policies, fn {participant_id, presence_policy} ->
        {participant_id, participant(participant_id, presence_policy)}
      end)

    %ResolvedCallPlan{
      definition_id: "definition-policy-authority",
      definition_revision: 1,
      schema_version: "20260911.01",
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
