defmodule Vxpipe.CallEngine.MediaPolicy.EffectiveTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy

  test "treats inherited routes as unrestricted and inherited storage permissions as allowed" do
    inherited = MediaPolicy.inherit()

    assert {:ok, effective} = Effective.compose(inherited, inherited, %{})

    assert effective.audio_routes == :unrestricted
    assert effective.transcript_routes == :unrestricted
    assert effective.record_audio
    assert effective.save_transcripts
    assert Effective.audio_route_permitted?(effective, "participant-a", "participant-b")
    assert Effective.transcript_route_permitted?(effective, "participant-a", "participant-b")
  end

  test "intersects complete route allowlists and applies false-wins storage permissions" do
    host_ceiling =
      policy(
        audio_routes: %{
          "caller-id" => ["agent-id", "specialist-id"],
          "agent-id" => ["caller-id"],
          "specialist-id" => ["caller-id"]
        },
        transcript_routes: %{
          "caller-id" => ["agent-id", "specialist-id"],
          "specialist-id" => ["caller-id"]
        },
        record_audio: true,
        save_transcripts: true
      )

    normal_policy =
      policy(
        audio_routes: %{
          "caller-id" => ["agent-id", "specialist-id", "monitor-id"],
          "agent-id" => ["caller-id"],
          "specialist-id" => ["caller-id", "agent-id"]
        },
        transcript_routes: %{
          "caller-id" => ["caller-id", "agent-id", "specialist-id"],
          "specialist-id" => ["caller-id", "agent-id"]
        }
      )

    specialist_restriction =
      policy(
        audio_routes: %{
          "caller-id" => ["specialist-id"],
          "specialist-id" => ["caller-id"]
        },
        transcript_routes: %{
          "caller-id" => ["caller-id", "specialist-id"],
          "specialist-id" => ["caller-id", "specialist-id"]
        },
        record_audio: false,
        save_transcripts: false
      )

    assert {:ok, effective} =
             Effective.compose(host_ceiling, normal_policy, %{
               "specialist-id" => specialist_restriction
             })

    assert effective.audio_routes == %{
             "caller-id" => MapSet.new(["specialist-id"]),
             "specialist-id" => MapSet.new(["caller-id"])
           }

    assert effective.transcript_routes == %{
             "caller-id" => MapSet.new(["specialist-id"]),
             "specialist-id" => MapSet.new(["caller-id"])
           }

    refute effective.record_audio
    refute effective.save_transcripts
    refute Effective.audio_route_permitted?(effective, "agent-id", "caller-id")
    refute Effective.audio_route_permitted?(effective, "caller-id", "agent-id")
    assert Effective.audio_route_permitted?(effective, "caller-id", "specialist-id")
  end

  test "keeps an explicitly intersected source with no permitted recipients" do
    inherited = MediaPolicy.inherit()

    first = policy(audio_routes: %{"caller-id" => ["agent-id"]})
    second = policy(audio_routes: %{"caller-id" => ["specialist-id"]})

    assert {:ok, effective} =
             Effective.compose(inherited, first, %{"specialist-id" => second})

    assert effective.audio_routes == %{"caller-id" => MapSet.new()}
    refute Effective.audio_route_permitted?(effective, "caller-id", "agent-id")
    refute Effective.audio_route_permitted?(effective, "caller-id", "specialist-id")
  end

  test "recomputing after leave removes only that participant's contribution" do
    inherited = MediaPolicy.inherit()

    normal_policy =
      policy(
        audio_routes: %{
          "caller-id" => ["agent-id", "specialist-id"],
          "agent-id" => ["caller-id"],
          "specialist-id" => ["caller-id"]
        },
        record_audio: true,
        save_transcripts: true
      )

    specialist_restriction =
      policy(
        audio_routes: %{
          "caller-id" => ["specialist-id"],
          "specialist-id" => ["caller-id"]
        },
        record_audio: false
      )

    observer_restriction = policy(save_transcripts: false)

    contributions = %{
      "specialist-id" => specialist_restriction,
      "observer-id" => observer_restriction
    }

    assert {:ok, restricted} = Effective.compose(inherited, normal_policy, contributions)
    refute restricted.record_audio
    refute restricted.save_transcripts

    assert {:ok, after_specialist_left} =
             Effective.compose(
               inherited,
               normal_policy,
               Map.delete(contributions, "specialist-id")
             )

    assert after_specialist_left.audio_routes == normal_policy.audio_routes
    assert after_specialist_left.record_audio
    refute after_specialist_left.save_transcripts
  end

  test "rejects malformed trusted inputs so a policy barrier can fail closed" do
    malformed = %{MediaPolicy.inherit() | audio_routes: %{"caller-id" => ["agent-id"]}}

    assert {:error, :invalid_policy} =
             Effective.compose(MediaPolicy.inherit(), malformed, %{})
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
