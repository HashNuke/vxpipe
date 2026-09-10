defmodule Vxpipe.CallEngine.RoomAuthority.SpokenHistoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition.TransferHistory
  alias Vxpipe.CallEngine.RoomAuthority.SpokenHistory

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
