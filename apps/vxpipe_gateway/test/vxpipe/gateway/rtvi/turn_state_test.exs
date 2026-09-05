defmodule Vxpipe.Gateway.RTVI.TurnStateTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    TextOutput
  }

  alias Vxpipe.Gateway.RTVI.TurnState

  test "keeps unaligned spoken output pending without muting participant input" do
    output = text_output("turn-1")
    speech_started = agent_speech_started("turn-1")
    turn_completed = agent_turn_completed("turn-1")

    state = TurnState.new()

    assert {state, [{:event, ^output}]} =
             TurnState.project(state, output)

    assert {state,
            [
              {:event, ^speech_started},
              {:spoken_progress, ^output, "evt_speech", :in_progress}
            ]} = TurnState.project(state, speech_started)

    progress = agent_speech_progressed("turn-1", 600, 1_000)

    assert {^state, []} = TurnState.project(state, progress)

    assert {_state,
            [
              {:spoken_progress, ^output, "evt_completed", :completed},
              {:event, ^turn_completed}
            ]} = TurnState.project(state, turn_completed)
  end

  test "sequences every queued spoken turn without server mute actions" do
    first = text_output("turn-1")
    second = %{text_output("turn-2") | id: "evt_output_2", sequence: 2}

    assert {state, [{:event, ^first}]} =
             TurnState.project(TurnState.new(), first)

    assert {state, []} = TurnState.project(state, second)

    assert {state,
            [
              {:spoken_progress, ^first, "evt_completed", :completed},
              {:event, _},
              {:event, ^second}
            ]} = TurnState.project(state, agent_turn_completed("turn-1"))

    assert {_state,
            [
              {:spoken_progress, ^second, "evt_completed", :completed},
              {:event, _}
            ]} = TurnState.project(state, agent_turn_completed("turn-2"))
  end

  test "advances streamed sentences while keeping one speaking turn open" do
    first = text_output("turn-1")
    second = %{text_output("turn-1") | id: "evt_output_2", sequence: 2, text: "Again."}
    first_started = agent_speech_started("turn-1")
    second_started = %{agent_speech_started("turn-1") | id: "evt_speech_2", sequence: 4}

    assert {state, [{:event, ^first}]} = TurnState.project(TurnState.new(), first)
    assert {state, []} = TurnState.project(state, second)

    assert {state, [{:event, ^first_started}, {:spoken_progress, ^first, _, :in_progress}]} =
             TurnState.project(state, first_started)

    assert {state,
            [
              {:spoken_progress, ^first, "evt_speech_2", :completed},
              {:event, ^second},
              {:spoken_progress, ^second, "evt_speech_2", :in_progress}
            ]} = TurnState.project(state, second_started)

    assert {_state,
            [
              {:spoken_progress, ^second, "evt_completed", :completed},
              {:event, _}
            ]} = TurnState.project(state, agent_turn_completed("turn-1"))
  end

  test "projects text-only output directly" do
    output = %{text_output("turn-1") | will_be_spoken: false}

    assert {_state, [{:event, ^output}]} = TurnState.project(TurnState.new(), output)
  end

  test "interrupts active output without claiming its remaining text was spoken" do
    output = text_output("turn-1")
    interruption = agent_turn_interrupted("turn-1")

    assert {state, [{:event, ^output}]} =
             TurnState.project(TurnState.new(), output)

    assert {state,
            [
              {:event, ^interruption},
              {:interruption_context, ^interruption}
            ]} = TurnState.project(state, interruption)

    refute Enum.any?(
             elem(TurnState.project(state, interruption), 1),
             &match?({:spoken_progress, _, _, :completed}, &1)
           )
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

  defp agent_turn_interrupted(correlation_id) do
    fields =
      "evt_interrupted"
      |> event_fields(correlation_id)
      |> Map.merge(%{
        interrupted_by_participant_id: "part-interrupter",
        interrupted_by_connection_id: "conn-interrupter",
        interruption_command_id: "cmd-interrupter",
        interruption_correlation_id: "turn-interrupter",
        played_ms: 20
      })

    struct!(AgentTurnInterrupted, fields)
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
