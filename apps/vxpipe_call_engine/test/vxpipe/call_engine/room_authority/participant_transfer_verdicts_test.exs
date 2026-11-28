defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.VerdictsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Verdicts
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  defp state(plan_guardrails, extra \\ %{}) do
    %{
      snapshot: %{incarnation_id: "incarnation-1"},
      participant_transfer_runtime: %{
        plan: %{
          call_spec_revision: 4,
          participants: %{
            "reception" => %{
              kind: :agent,
              participant_id: "part-reception",
              guardrails: %{before_outgoing_transfer: plan_guardrails}
            }
          }
        }
      },
      transfer_verdicts: Map.get(extra, :transfer_verdicts, %{}),
      text_capability: Map.get(extra, :text_capability, :text_capability),
      speech_to_speech_capability: nil,
      speech_to_speech_runtime: nil,
      connections: %{
        "connection-1" => %{participant_id: "caller-1"}
      },
      participant_ids: MapSet.new(["caller-1"])
    }
  end

  defp questions do
    [
      %{
        id: "wrong_department",
        question: "Is the requested destination unrelated?",
        required_answer: :no,
        threshold_hundredths: 70,
        response: "Ask which department the caller needs."
      }
    ]
  end

  defp digest, do: Vxpipe.CallEngine.Guardrails.TransferAdmission.policy_digest(questions())

  defp request(overrides \\ %{}) do
    %Request{
      tenant_id: "tenant-1",
      room_id: "room-1",
      incarnation_id: "incarnation-1",
      source_call_spec_key: "reception",
      source_participant_id: "part-reception",
      source_activation_id: "activation-1",
      source_capability: self(),
      caller_participant_id: "caller-1",
      connection_id: "connection-1",
      command_id: "command-1",
      correlation_id: "turn-1",
      tool_call_id: "transfer-1",
      destination_call_spec_key: "billing",
      destination_participant_id: "part-billing",
      reason: nil
    }
    |> Map.merge(Map.new(overrides))
  end

  defp entry(overrides \\ %{}) do
    Map.merge(
      %{
        invocation_id: "transfer-1",
        command_id: "command-1",
        expires_at_ms: System.monotonic_time(:millisecond) + 30_000,
        verdict: :passed,
        source_activation_id: "activation-1",
        source_participant_id: "part-reception",
        destination_call_spec_key: "billing",
        policy_digest: digest(),
        policy_revision: 4,
        incarnation_id: "incarnation-1",
        checked_at_ms: System.monotonic_time(:millisecond),
        source: :bound
      },
      Map.new(overrides)
    )
  end

  defp bind!(state, entry) do
    {:ok, next} = Verdicts.bind(state, entry)
    next
  end

  test "bind stores a passed verdict keyed by invocation" do
    state = bind!(state(questions()), entry())
    assert %{transfer_verdicts: %{{"command-1", "transfer-1"} => %{verdict: :passed}}} = state
  end

  test "bind rejects malformed entries without touching state" do
    before = state(questions())
    assert {:error, :invalid_verdict} = Verdicts.bind(before, %{invocation_id: "transfer-1"})
  end

  test "blank identities and unbounded deadlines cannot reserve a room verdict" do
    room = state(questions())
    assert {:error, :invalid_verdict} = Verdicts.bind(room, entry(%{command_id: ""}))

    assert {:error, :invalid_verdict} =
             Verdicts.bind(room, entry(%{expires_at_ms: 18_446_744_073_709_551_616}))
  end

  test "consume honors a fresh bound verdict and deletes it" do
    room = bind!(state(questions()), entry())

    assert {:ok, stamped, room} = Verdicts.consume(room, request())
    assert stamped.transfer_admission.source == :bound
    assert stamped.transfer_admission.policy_digest == digest()
    assert room.transfer_verdicts == %{}
  end

  test "an unbound worker stamp cannot authorize another destination or be replayed" do
    stamp = %{
      verdict: :passed,
      policy_digest: digest(),
      checked_at_ms: System.monotonic_time(:millisecond),
      source: :checked
    }

    request = request(%{transfer_admission: stamp})
    assert {:error, _, _room} = Verdicts.consume(state(questions()), request)

    assert {:error, _, _room} =
             Verdicts.consume(state(questions()), %{
               request
               | destination_call_spec_key: "support"
             })

    bound = bind!(state(questions()), entry(%{source: :checked}))
    assert {:ok, stamped, room} = Verdicts.consume(bound, request)
    assert stamped.transfer_admission.source == :checked
    assert {:error, _, _room} = Verdicts.consume(room, stamped)
  end

  test "consume passes through when no transfer questions are configured" do
    assert {:ok, request, room} = Verdicts.consume(state([]), request())
    assert request.transfer_admission == nil
    assert room.transfer_verdicts == %{}
  end

  test "removing a checked policy discards the old bound invocation" do
    stored = bind!(state(questions()), entry())
    changed = state([], %{transfer_verdicts: stored.transfer_verdicts})
    assert {:error, :stale, next} = Verdicts.consume(changed, request())
    assert next.transfer_verdicts == %{}
  end

  test "a different command cannot spend or destroy a passed verdict with the same provider id" do
    room = bind!(state(questions()), entry())
    assert {:error, _, room} = Verdicts.consume(room, request(%{command_id: "command-2"}))
    assert {:ok, _, _} = Verdicts.consume(room, request())
  end

  test "a new command supersedes abandoned entries from the same source" do
    old = bind!(state(questions()), entry())
    later = entry(%{command_id: "later", invocation_id: "new-transfer"})
    current = bind!(old, later)
    assert map_size(current.transfer_verdicts) == 1
    assert {:error, _, _} = Verdicts.consume(current, request())

    assert {:ok, _, _} =
             Verdicts.consume(
               current,
               request(%{command_id: "later", tool_call_id: "new-transfer"})
             )
  end

  test "room refuses a malformed bind and expires an unused entry before another event" do
    alias Vxpipe.CallEngine.RoomAuthority

    state =
      struct(
        RoomAuthority.State,
        Map.take(state(questions()), [:participant_transfer_runtime, :snapshot])
      )

    assert {:reply, {:error, _}, ^state} =
             RoomAuthority.handle_call(
               {:bind_transfer_verdict, %{invocation_id: "bad"}},
               {self(), make_ref()},
               state
             )

    short = entry(%{expires_at_ms: System.monotonic_time(:millisecond) + 50})

    assert {:reply, :ok, bound} =
             RoomAuthority.handle_call(
               {:bind_transfer_verdict, short},
               {self(), make_ref()},
               state
             )

    assert_receive {:timeout, _timer, {:transfer_verdict, _key}} = expiry
    assert {:error, _, _} = Verdicts.consume(bound, request())
    assert {:noreply, %{transfer_verdicts: empty}} = RoomAuthority.handle_info(expiry, bound)
    assert empty == %{}
  end

  test "consume fences a stale verdict on incarnation change and drops it" do
    room = bind!(state(questions()), entry())
    stale_request = request(%{incarnation_id: "incarnation-2"})

    assert {:error, :stale, room} = Verdicts.consume(room, stale_request)
    assert room.transfer_verdicts == %{}
  end

  test "consume fences a destination change and drops the bound verdict" do
    room = bind!(state(questions()), entry())
    changed = request(%{destination_call_spec_key: "support"})

    assert {:error, :stale, room} = Verdicts.consume(room, changed)
    assert room.transfer_verdicts == %{}
  end

  test "consume fences a policy change and drops the bound verdict" do
    room = bind!(state(questions()), entry(%{policy_digest: "old-digest"}))

    assert {:error, :stale, room} = Verdicts.consume(room, request())
    assert room.transfer_verdicts == %{}
  end

  test "a new policy revision invalidates both a pending verdict and an admitted announcement" do
    room = bind!(state(questions()), entry())
    assert {:ok, admitted, _} = Verdicts.consume(room, request())
    assert Verdicts.current_after_announcement?(room, admitted)

    updated = put_in(room, [:participant_transfer_runtime, :plan, :call_spec_revision], 5)
    assert {:error, :stale} = Verdicts.validate(updated, request())
    assert {:error, :stale, %{transfer_verdicts: %{}}} = Verdicts.consume(updated, request())
    refute Verdicts.current_after_announcement?(updated, admitted)
  end

  test "consume fails closed when questions exist but no verdict is present" do
    assert {:error, :unchecked, _room} = Verdicts.consume(state(questions()), request())
  end

  test "drop_for_source clears only the affected activation entries" do
    room =
      state(questions())
      |> bind!(entry())
      |> bind!(entry(%{invocation_id: "transfer-2", source_activation_id: "activation-2"}))

    room = Verdicts.drop_for_source(room, "activation-1")

    assert Map.keys(room.transfer_verdicts) == [{"command-1", "transfer-2"}]
  end

  test "drop_for_participant clears entries when the source is torn down" do
    room =
      state(questions())
      |> bind!(entry())
      |> bind!(entry(%{invocation_id: "transfer-2", source_participant_id: "other"}))

    room = Verdicts.drop_for_participant(room, "part-reception")

    assert Map.keys(room.transfer_verdicts) == [{"command-1", "transfer-2"}]
  end
end
