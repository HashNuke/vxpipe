defmodule Vxpipe.CallEngine.RoomAuthority.SpokenHistoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.TransferHistory
  alias Vxpipe.CallEngine.RoomAuthority.SpokenHistory

  test "preserves trusted input and spoken output attribution through transfer" do
    alias Vxpipe.AgentRuntime.Input
    alias Vxpipe.CallEngine.Command.SendText
    alias Vxpipe.CallEngine.TextToSpeechRequest

    {:ok, input} = Input.participant("human-one", "Actually, Friday", :speaker)

    command =
      struct!(SendText,
        id: "command-one",
        tenant_id: "tenant",
        actor_id: "actor",
        room_id: "room",
        incarnation_id: "incarnation",
        participant_id: "human-one",
        connection_id: "connection",
        correlation_id: "correlation",
        content: "Actually, Friday",
        run_immediately: true,
        audio_response: true,
        deadline: DateTime.utc_now(),
        model_input: input
      )

    request =
      struct!(TextToSpeechRequest,
        tenant_id: "tenant",
        room_id: "room",
        incarnation_id: "incarnation",
        participant_id: "agent-original",
        source_participant_id: "human-one",
        connection_id: "connection",
        command_id: "command-one",
        correlation_id: "correlation",
        output_id: "output-one",
        text: "Friday works.",
        output_sink: self(),
        output_generation: 0
      )

    history =
      SpokenHistory.new()
      |> SpokenHistory.confirm_user(command)
      |> SpokenHistory.played_assistant(request)

    [human, agent] = SpokenHistory.project(history, policy(:all_spoken))
    assert human.content == Input.encode(input)

    assert JSON.decode!(agent.content) == %{
             "type" => "participant_message",
             "participant_id" => "agent-original",
             "message" => "Friday works.",
             "agent_mode" => "speaker"
           }

    assert SpokenHistory.project(history, policy(:last_n_spoken, 1)) == [agent]
  end

  test "projects only confirmed user and played assistant utterances under the pinned mode" do
    history =
      SpokenHistory.new()
      |> SpokenHistory.confirm_user("First caller turn")
      |> SpokenHistory.played_assistant("First played answer")
      |> SpokenHistory.confirm_user("Second caller turn")
      |> SpokenHistory.played_assistant("Second played answer")

    assert SpokenHistory.project(history, policy(:fresh)) == []
    assert SpokenHistory.project(history, policy(:selected)) == []

    assert project_content(history, policy(:all_spoken)) == [
             {:user, "First caller turn"},
             {:assistant, "First played answer"},
             {:user, "Second caller turn"},
             {:assistant, "Second played answer"}
           ]

    assert project_content(history, policy(:last_n_spoken, 2)) == [
             {:user, "Second caller turn"},
             {:assistant, "Second played answer"}
           ]

    refute inspect(history) =~ "First caller turn"
    refute inspect(history) =~ "First played answer"
  end

  defp project_content(history, policy) do
    history
    |> SpokenHistory.project(policy)
    |> Enum.map(&{&1.role, &1.content})
  end

  defp policy(mode, turns \\ nil), do: %TransferHistory{mode: mode, turns: turns}
end
