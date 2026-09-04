defmodule Vxpipe.Gateway.RTVI.TurnStateTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    TextOutput
  }

  alias Vxpipe.Gateway.RTVI.TurnState

  test "suppresses input and projects a complete RTVI 2.x spoken-output lifecycle" do
    output = text_output("turn-1")
    speech_started = agent_speech_started("turn-1")
    turn_completed = agent_turn_completed("turn-1")

    state = TurnState.new()
    assert TurnState.input_enabled?(state)

    assert {state, [{:event, ^output}, {:user_mute, :started, "evt_output"}]} =
             TurnState.project(state, output)

    refute TurnState.input_enabled?(state)

    assert {state,
            [
              {:event, ^speech_started},
              {:spoken_progress, ^output, "evt_speech", :in_progress}
            ]} = TurnState.project(state, speech_started)

    progress = agent_speech_progressed("turn-1", 600, 1_000)

    assert {state,
            [
              {:spoken_progress, ^output, "evt_progress", {:in_progress, 600, 1_000}}
            ]} = TurnState.project(state, progress)

    assert {state,
            [
              {:spoken_progress, ^output, "evt_completed", :completed},
              {:event, ^turn_completed},
              {:user_mute, :stopped, "evt_completed"}
            ]} = TurnState.project(state, turn_completed)

    assert TurnState.input_enabled?(state)
  end

  test "keeps input suppressed until every queued spoken turn completes" do
    first = text_output("turn-1")
    second = %{text_output("turn-2") | id: "evt_output_2", sequence: 2}

    assert {state, [{:event, ^first}, {:user_mute, :started, "evt_output"}]} =
             TurnState.project(TurnState.new(), first)

    assert {state, []} = TurnState.project(state, second)

    assert {state,
            [
              {:spoken_progress, ^first, "evt_completed", :completed},
              {:event, _},
              {:event, ^second}
            ]} = TurnState.project(state, agent_turn_completed("turn-1"))

    refute TurnState.input_enabled?(state)

    assert {state,
            [
              {:spoken_progress, ^second, "evt_completed", :completed},
              {:event, _},
              {:user_mute, :stopped, "evt_completed"}
            ]} = TurnState.project(state, agent_turn_completed("turn-2"))

    assert TurnState.input_enabled?(state)
  end

  test "does not suppress input for text-only output" do
    output = %{text_output("turn-1") | will_be_spoken: false}

    assert {state, [{:event, ^output}]} = TurnState.project(TurnState.new(), output)
    assert TurnState.input_enabled?(state)
  end

  defp text_output(correlation_id) do
    %TextOutput{
      id: "evt_output",
      sequence: 1,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-text",
      correlation_id: correlation_id,
      text: "Echo: hello",
      aggregated_by: :sentence,
      will_be_spoken: true,
      occurred_at: ~U[2026-09-04 20:00:00.000Z]
    }
  end

  defp agent_speech_started(correlation_id) do
    struct!(AgentSpeechStarted, event_fields("evt_speech", correlation_id))
  end

  defp agent_turn_completed(correlation_id) do
    struct!(AgentTurnCompleted, event_fields("evt_completed", correlation_id))
  end

  defp agent_speech_progressed(correlation_id, played_ms, total_ms) do
    fields =
      "evt_progress"
      |> event_fields(correlation_id)
      |> Map.merge(%{played_ms: played_ms, total_ms: total_ms})

    struct!(AgentSpeechProgressed, fields)
  end

  defp event_fields(id, correlation_id) do
    %{
      id: id,
      sequence: 2,
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-agent",
      source_participant_id: "part-human",
      connection_id: "conn-demo",
      command_id: "cmd-text",
      correlation_id: correlation_id,
      occurred_at: ~U[2026-09-04 20:00:01.000Z]
    }
  end
end
