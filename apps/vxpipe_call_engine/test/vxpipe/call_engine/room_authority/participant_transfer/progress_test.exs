defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.ProgressTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{Pending, Progress}
  alias Vxpipe.CallEngine.RoomAuthority.State

  test "keeps the promoted destination informed while excluding unrelated connections" do
    connections =
      Map.new(["caller", "destination", "unrelated"], fn id ->
        {id, %{pid: recipient(id), admission: :main, transfer_attempt_id: nil}}
      end)

    pending =
      struct(Pending,
        attempt_id: "handoff",
        deadline_ms: System.monotonic_time(:millisecond) + 5_000,
        destination_connection_id: "destination",
        request: %{connection_id: "caller", destination_call_spec_key: "support"}
      )

    state =
      struct(State,
        connections: connections,
        participant_transfer_runtime: %{plan: %{transfer_policy: %{attempt_timeout_ms: 5_000}}}
      )

    assert :ok = Progress.publish(pending, :preparing, [:speech_to_text], state)

    for id <- ["caller", "destination"] do
      assert_receive {^id,
                      {:vxpipe_transfer_progress, "handoff",
                       %{phase: :preparing, blockers: [:speech_to_text]}}}
    end

    refute_receive {"unrelated", _progress}
  end

  defp recipient(id) do
    observer = self()

    start_supervised!(
      {Task,
       fn ->
         receive do
           message -> send(observer, {id, message})
         end
       end},
      id: {Task, id}
    )
  end
end
