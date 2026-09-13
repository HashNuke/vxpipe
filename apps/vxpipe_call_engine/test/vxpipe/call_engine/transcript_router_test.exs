defmodule Vxpipe.CallEngine.TranscriptRouterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.TranscriptRouter
  alias Vxpipe.CallEngine.TranscriptRouter.{Decision, Projection}

  @identity %{
    tenant_id: "tenant-transcript",
    room_id: "room-transcript",
    incarnation_id: "incarnation-transcript"
  }

  test "routes a current transcript and pins its storage permission to the source revision" do
    router = start_router()
    :ok = apply_policy(router, 0, ["alice", "bob"])

    assert {:ok,
            %Decision{
              recipient_participant_ids: recipients,
              source_policy: %{
                "media_policy_revision" => 0,
                "save_transcripts" => true
              }
            }} = TranscriptRouter.project(router, projection(0, "alice", ["alice", "bob"]))

    assert recipients == MapSet.new(["alice", "bob"])

    routes = %{"alice" => MapSet.new(["bob"])}

    :ok =
      apply_policy(router, 1, ["alice", "bob"],
        transcript_routes: routes,
        save_transcripts: false
      )

    assert {:ok,
            %Decision{
              recipient_participant_ids: recipients,
              source_policy: %{
                "media_policy_revision" => 1,
                "save_transcripts" => false
              }
            }} =
             TranscriptRouter.project(
               router,
               projection(1, "alice", ["alice", "bob"])
             )

    assert recipients == MapSet.new(["bob"])
  end

  test "never delivers a stale interval after a later restriction or relaxation" do
    router = start_router()
    :ok = apply_policy(router, 0, ["alice", "bob"])

    :ok =
      apply_policy(router, 1, ["alice", "bob"],
        transcript_routes: %{},
        save_transcripts: false
      )

    :ok = apply_policy(router, 2, ["alice", "bob"])

    assert {:ok,
            %Decision{
              recipient_participant_ids: recipients,
              source_policy: %{
                "media_policy_revision" => 1,
                "save_transcripts" => false
              }
            }} = TranscriptRouter.project(router, projection(1, "alice", ["alice", "bob"]))

    assert recipients == MapSet.new()
  end

  test "rejects untrusted identity, unknown revisions, and absent sources" do
    router = start_router()
    :ok = apply_policy(router, 0, ["alice"])

    assert {:error, :wrong_room} =
             TranscriptRouter.project(
               router,
               projection(0, "alice", ["alice"], room_id: "other-room")
             )

    assert {:error, :unknown_policy_revision} =
             TranscriptRouter.project(router, projection(4, "alice", ["alice"]))

    assert {:error, :source_not_present} =
             TranscriptRouter.project(router, projection(0, "missing", ["alice"]))
  end

  test "retains an active speech interval across unrelated revisions" do
    router = start_router(maximum_retained_revisions: 2)
    :ok = apply_policy(router, 0, ["alice", "bob"])
    :ok = apply_policy(router, 1, ["alice", "bob", "carol"])
    :ok = apply_policy(router, 2, ["alice", "bob"], audio_routes: %{})
    :ok = apply_policy(router, 3, ["alice", "bob"])

    assert {:ok, %Decision{recipient_participant_ids: recipients}} =
             TranscriptRouter.project(router, projection(0, "alice", ["bob"]))

    assert recipients == MapSet.new(["bob"])
  end

  test "bounds retained source-policy revisions and fails closed after eviction" do
    router = start_router(maximum_retained_revisions: 2)
    :ok = apply_policy(router, 0, ["alice"])
    :ok = apply_policy(router, 1, ["alice"], save_transcripts: false)
    :ok = apply_policy(router, 2, ["alice"])

    assert %{policy_revision: 2, retained_policy_revisions: 2} =
             TranscriptRouter.stats(router)

    assert {:error, :unknown_policy_revision} =
             TranscriptRouter.project(router, projection(0, "alice", ["alice"]))

    assert {:ok, %Decision{recipient_participant_ids: recipients}} =
             TranscriptRouter.project(router, projection(1, "alice", ["alice"]))

    assert recipients == MapSet.new()
  end

  defp start_router(overrides \\ []) do
    options =
      Keyword.merge(
        [
          tenant_id: @identity.tenant_id,
          room_id: @identity.room_id,
          incarnation_id: @identity.incarnation_id,
          maximum_retained_revisions: 8,
          register: false
        ],
        overrides
      )

    start_supervised!({TranscriptRouter, options})
  end

  defp apply_policy(router, revision, participants, overrides \\ []) do
    effective =
      struct!(
        Effective,
        Keyword.merge(
          [
            audio_routes: :unrestricted,
            transcript_routes: :unrestricted,
            record_audio: true,
            save_transcripts: true
          ],
          overrides
        )
      )

    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(participants),
      effective: effective
    }

    Enforcer.apply(router, snapshot, 1_000)
  end

  defp projection(revision, source, recipients, overrides \\ []) do
    fields =
      @identity
      |> Map.merge(%{
        source_participant_id: source,
        policy_revision: revision,
        recipient_participant_ids: MapSet.new(recipients)
      })
      |> Map.merge(Map.new(overrides))

    struct!(Projection, fields)
  end
end
