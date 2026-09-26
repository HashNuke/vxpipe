defmodule Vxpipe.CallEngine.Capability.ResponseOriginsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.ResponseOrigins

  test "drops stale accepted contexts but keeps current and referenced ones" do
    base = state(%{})
    {:ok, current} = ResponseOrigins.fingerprint(base)
    referenced = make_ref()
    current_context = make_ref()
    stale = make_ref()

    accepted =
      Map.new([
        {referenced, %{stale: true}},
        {current_context, current},
        {stale, %{stale: true}}
      ])

    pending = [{:response, make_ref(), referenced, %{stale: true}, 1}]

    state = %{base | response_origins: %{base.response_origins | accepted: accepted}}
    pruned = ResponseOrigins.prune(%{state | pending_turns: pending})
    keys = pruned.response_origins.accepted |> Map.keys() |> Enum.sort()
    assert keys == Enum.sort([referenced, current_context])
  end

  test "pruning stale contexts frees capacity below the 16-context bound" do
    accepted = Map.new(for _ <- 1..16, do: {make_ref(), %{stale: true}})

    pruned = ResponseOrigins.prune(state(accepted))
    assert map_size(pruned.response_origins.accepted) == 0
    assert map_size(pruned.response_origins.accepted) < 16
  end

  defp state(accepted, pending_turns \\ []) do
    %{
      descriptor: %{response_start?: true},
      response_origins: %{current: nil, accepted: accepted},
      pending_turns: pending_turns,
      external_activity_origin: nil,
      held?: false,
      input_epoch: make_ref(),
      human_id: "human",
      agent_id: "agent",
      caller_source: :sts,
      frame_identity: %{},
      origin_lifecycle_revision: make_ref(),
      origin_policy_revision: 0,
      policy_revision: 0,
      input_policy: nil,
      policy: nil,
      session: %{generation: make_ref()}
    }
  end
end
