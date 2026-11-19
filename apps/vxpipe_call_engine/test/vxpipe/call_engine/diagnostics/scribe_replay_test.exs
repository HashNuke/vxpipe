defmodule Vxpipe.CallEngine.Diagnostics.ScribeReplayTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.ScribeReplay
  alias Vxpipe.CallEngine.Speech.CapabilityTree

  setup do
    tree = start_supervised!({CapabilityTree, owner: self()})
    %{scope: CapabilityTree.scope(tree)}
  end

  test "committed segments do not end a turn until the actual adapter settles", %{scope: scope} do
    steps = [
      {100_000, {:segment, "synthetic first"}},
      {200_000, {:partial, ""}},
      {300_000, {:partial, ""}}
    ]

    assert {:ok, [%{provider_text_commit: 100_000, provider_end_received: 200_000}]} =
             ScribeReplay.run(scope, steps)
  end

  test "outstanding draft and forced segments retain one turn without manufacturing endpoints", %{
    scope: scope
  } do
    steps = [
      {100_000, {:segment, "first"}},
      {150_000, {:partial, "draft"}},
      {200_000, {:partial, ""}},
      {250_000, {:segment, "second"}},
      {300_000, {:partial, ""}}
    ]

    assert {:ok, [%{provider_text_commit: 250_000, provider_end_received: 300_000}]} =
             ScribeReplay.run(scope, steps)
  end

  test "manual flush acknowledgement is still a segment rather than provider end", %{scope: scope} do
    steps = [
      {100_000, {:segment, "first"}},
      {150_000, {:partial, "draft"}},
      {180_000, :await_manual_commit},
      {200_000, {:segment, "final draft"}},
      {300_000, {:partial, ""}}
    ]

    assert {:ok,
            [
              %{
                manual_commit_sent: 180_000,
                provider_text_commit: 200_000,
                provider_end_received: 300_000
              }
            ]} = ScribeReplay.run(scope, steps, draft_flush_gap_ms: 1)
  end

  test "an earlier turn's unconsumed manual commit cannot be assigned to the next turn", %{
    scope: scope
  } do
    whitespace = String.duplicate(" ", 65_536)

    steps =
      [{100, {:segment, "first"}}, {150, {:partial, "draft"}}] ++
        Enum.map(1..128, fn index -> {150 + index, {:partial, whitespace}} end) ++
        [
          {500, {:segment, "committed draft"}},
          {600, {:partial, ""}},
          {700, {:segment, "next turn"}},
          {800, :await_manual_commit}
        ]

    assert {:error, _reason} = ScribeReplay.run(scope, steps, draft_flush_gap_ms: 1)
  end

  test "no provider end is inferred from a committed-only or partial-only trace", %{scope: scope} do
    assert {:ok, [landmarks]} = ScribeReplay.run(scope, [{100_000, {:segment, "unfinished"}}])
    refute Map.has_key?(landmarks, :provider_end_received)
  end
end
