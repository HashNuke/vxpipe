defmodule Vxpipe.CallEngine.Guardrails.ParticipantTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.Guardrails
  alias Vxpipe.CallEngine.Guardrails.Participant

  setup do
    {:ok, policy} =
      Guardrails.new(
        %{
          "before_turn" => [
            %{"id" => "first", "question" => "Is this supported?", "required_answer" => "yes"}
          ],
          "after_turn" => [
            %{"id" => "second", "question" => "Is this private?", "required_answer" => "no"}
          ]
        },
        []
      )

    parent = self()

    adapter = fn request ->
      send(parent, {:issued, self(), request})

      receive do
        {:answer, scores} -> {:ok, %{scores: scores, model: "fixture"}}
        {:provider_error, reason} -> {:error, reason}
      end
    end

    tasks = start_supervised!(Task.Supervisor)

    participant =
      start_supervised!(
        {Participant, policy: policy, request_supervisor: tasks, adapter: adapter}
      )

    %{participant: participant}
  end

  test "an unanswered guardrail prevents admission until its result arrives", %{
    participant: participant
  } do
    check =
      Task.async(fn ->
        Participant.check(participant, :before_turn, "proposal", %{"text" => "Hi"}, deadline())
      end)

    assert_receive {:issued, worker,
                    %{questions: [%{id: "first", question: "Is this supported?"}]}}

    send(worker, {:answer, %{"first" => 0.3}})
    assert {:blocked, ["Failed guardrail: Is this supported? Required: Yes."]} = Task.await(check)
  end

  test "an empty event skips the adapter", %{participant: participant} do
    assert :passed =
             Participant.check(
               participant,
               :before_outgoing_transfer,
               "proposal",
               %{},
               deadline()
             )

    refute_received {:issued, _, _}
  end

  test "owner loss cancels pending work and frees the participant", %{participant: participant} do
    caller = spawn(fn -> Participant.check(participant, :before_turn, "old", %{}, deadline()) end)
    assert_receive {:issued, worker, _}
    ref = Process.monitor(worker)
    assert {:error, :busy} = Participant.check(participant, :before_turn, "new", %{}, deadline())
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}

    check =
      Task.async(fn -> Participant.check(participant, :after_turn, "new", %{}, deadline()) end)

    assert_receive {:issued, worker, _}
    send(worker, {:answer, %{"second" => 0.1}})
    assert :passed = Task.await(check)
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 2_000

  test "preserves adapter errors and distinguishes cancellation from expiration", %{
    participant: participant
  } do
    for reason <- [:unauthorized, :transport_error, :cancelled, :stale, :timeout] do
      check =
        Task.async(fn ->
          Participant.check(participant, :before_turn, "proposal", %{}, deadline())
        end)

      assert_receive {:issued, worker, _request}
      send(worker, {:provider_error, reason})
      assert {:error, ^reason} = Task.await(check)
    end
  end
end
