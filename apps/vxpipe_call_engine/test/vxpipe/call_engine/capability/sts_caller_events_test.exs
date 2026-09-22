defmodule Vxpipe.CallEngine.Capability.STSCallerEventsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.CallerEvents
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.Speech.Event

  test "denied final text does not retain completed caller associations" do
    state = state()
    state = %{state | policy: %{state.policy | transcript_routes: %{}}}

    Enum.reduce(1..20, state, fn index, state ->
      turn = make_ref()

      {:ok, state} =
        CallerEvents.forward(state, %Event{
          kind: :speech_started,
          turn_ref: turn,
          sequence: index * 2 - 1
        })

      assert_receive {:vxpipe_sts_input_event, _, %{event: %{kind: :speech_started}}}

      {:ok, state} =
        CallerEvents.forward(state, %Event{
          kind: :turn_ended,
          turn_ref: turn,
          sequence: index * 2,
          text: "FORBIDDEN"
        })

      assert_receive {:vxpipe_sts_input_event, _, %{event: %{kind: :turn_ended, text: nil}}}
      assert state.caller_turns == %{}
      state
    end)
  end

  test "onset policy intervals cannot be relabeled after revoke and regrant" do
    state = state()
    turn = make_ref()

    snapshot = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["human", "agent"]),
      effective: state.policy
    }

    {:ok, snapshot} = Snapshot.prepare(snapshot, nil)
    state = %{state | input_policy: snapshot}

    {:ok, state} =
      CallerEvents.forward(state, %Event{kind: :speech_started, turn_ref: turn, sequence: 1})

    assert_receive {:vxpipe_sts_input_event, _, %{transcript_interval: 0, audio_interval: 0}}

    {:ok, denied} =
      Snapshot.prepare(
        %{
          snapshot
          | revision: 1,
            intervals: nil,
            effective: %{snapshot.effective | transcript_routes: %{}}
        },
        snapshot
      )

    {:ok, restored} = Snapshot.prepare(%{snapshot | revision: 2, intervals: nil}, denied)
    state = %{state | input_policy: restored, policy_revision: 2}

    {:ok, state} =
      CallerEvents.forward(state, %Event{
        kind: :input_transcript,
        turn_ref: turn,
        sequence: 2,
        text: "OLD",
        final: true
      })

    refute_received {:vxpipe_sts_input_event, _, _}
    assert state.caller_turns == %{}
  end

  test "the caller association budget is independent of generated-output credit" do
    state =
      Enum.reduce(1..16, state(), fn index, state ->
        {:ok, state} =
          CallerEvents.forward(state, %Event{
            kind: :speech_started,
            turn_ref: make_ref(),
            sequence: index
          })

        assert_receive {:vxpipe_sts_input_event, _, %{event: %{kind: :speech_started}}}
        state
      end)

    assert {:error, :pending_caller_overflow} =
             CallerEvents.forward(state, %Event{
               kind: :speech_started,
               turn_ref: make_ref(),
               sequence: 17
             })

    refute_received {:vxpipe_sts_input_event, _, _}
  end

  defp state do
    %{
      caller_source: :sts,
      caller_turns: %{},
      owner: self(),
      held?: false,
      human_id: "human",
      agent_id: "agent",
      frame_identity: %{participant_id: "human"},
      input_epoch: make_ref(),
      input_policy: nil,
      policy_revision: 0,
      policy: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }
  end
end
