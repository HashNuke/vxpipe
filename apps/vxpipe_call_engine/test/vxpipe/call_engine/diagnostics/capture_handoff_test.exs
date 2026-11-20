defmodule Vxpipe.CallEngine.Diagnostics.CaptureHandoffTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.Media.AudioFrame

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  test "explicit retirement retains its source boundary" do
    assert {:ok, handoff} = new_handoff()
    assert :ok = CaptureHandoff.close(handoff)
    refute CaptureHandoff.current?(handoff)
    assert CaptureHandoff.closed_reason(handoff) == :source_changed
  end

  test "count and bytes remain reserved until queued or in-flight evidence is released" do
    assert {:ok, handoff} = new_handoff(maximum_count: 1)
    assert :ok = CaptureHandoff.offer(handoff, {:audio, frame()})
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, {:audio, _frame}, charge} = CaptureHandoff.message(handoff, message)
    assert {:error, :full} = CaptureHandoff.offer(handoff, {:audio, frame()})

    assert %{pending_count: 1, pending_bytes: ^charge, overflow: 1} =
             CaptureHandoff.stats(handoff)

    assert :ok = CaptureHandoff.release(handoff, charge, :processed)
    assert :ok = CaptureHandoff.offer(handoff, {:audio, frame()})
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = queued
    assert :ok = CaptureHandoff.close(handoff)
    assert {:error, :revoked} = CaptureHandoff.message(handoff, queued)
    assert %{pending_count: 0, pending_bytes: 0} = CaptureHandoff.stats(handoff)

    assert {:ok, bytes_limited} = new_handoff(maximum_bytes: 1_024)
    assert {:error, :full} = CaptureHandoff.offer(bytes_limited, {:audio, frame()})
    assert %{pending_count: 0, pending_bytes: 0} = CaptureHandoff.stats(bytes_limited)
  end

  for limit <- [:count, :bytes] do
    @limit limit
    test "#{limit} overflow is shared with its collector without changing local queue accounting" do
      assert {:ok, collector} = new_handoff()
      options = if @limit == :count, do: [maximum_count: 1], else: [maximum_bytes: 1_024]
      assert {:ok, input} = new_handoff(Keyword.put(options, :provenance, collector))
      assert {:ok, unrelated} = new_handoff()
      refute CaptureHandoff.overflowed?(collector)

      if @limit == :count, do: assert(:ok = CaptureHandoff.offer(input, {:audio, frame()}))
      assert {:error, :full} = CaptureHandoff.offer(input, {:audio, frame()})
      assert CaptureHandoff.overflowed?(input)
      assert CaptureHandoff.overflowed?(collector)
      refute CaptureHandoff.overflowed?(unrelated)
      assert CaptureHandoff.stats(collector).overflow == 0
      assert CaptureHandoff.closed_reason(collector) == nil

      assert :ok = CaptureHandoff.close(input)
      assert CaptureHandoff.closed_reason(collector) == :source_changed
      assert CaptureHandoff.overflowed?(collector)
      assert :ok = CaptureHandoff.close(collector)
      assert CaptureHandoff.overflowed?(collector)
    end
  end

  test "accepted audio is detached from large backing binaries before delivery" do
    backing = :binary.copy(<<1, 0>>, 1_000_000)
    pcm = binary_part(backing, 0, 640)
    assert :binary.referenced_byte_size(pcm) > byte_size(pcm)
    assert {:ok, handoff} = new_handoff()
    assert :ok = CaptureHandoff.offer(handoff, {:audio, %{frame() | payload: pcm}})
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, {:audio, copied}, charge} = CaptureHandoff.message(handoff, message)
    assert copied.payload == pcm
    assert :binary.referenced_byte_size(copied.payload) == 640
    assert :ok = CaptureHandoff.release(handoff, charge, :processed)
  end

  test "concurrent producers cannot grow the receiver queue beyond reserved capacity" do
    assert {:ok, handoff} = new_handoff(maximum_count: 4)

    results =
      1..64
      |> Task.async_stream(fn _ -> CaptureHandoff.offer(handoff, {:audio, frame()}) end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.to_list()

    assert Enum.count(results, &(&1 == {:ok, :ok})) == 4
    assert Enum.count(results, &(&1 == {:ok, {:error, :full}})) == 60
    assert %{pending_count: 4, overflow: 60} = CaptureHandoff.stats(handoff)

    for _ <- 1..4 do
      assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
      assert {:ok, _packet, charge} = CaptureHandoff.message(handoff, message)
      CaptureHandoff.release(handoff, charge, :processed)
    end

    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "probability evidence is bounded and carries reset epoch without PCM or transcripts" do
    assert {:ok, handoff} = new_handoff()
    evidence = {:probabilities, 4, 512, [0.1, 0.9], -10_000}
    assert :ok = CaptureHandoff.offer(handoff, evidence)
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, ^evidence, charge} = CaptureHandoff.message(handoff, message)
    assert :ok = CaptureHandoff.release(handoff, charge, :processed)

    for invalid <- [
          {:probabilities, 4, 512, List.duplicate(0.5, 33), 0},
          {:probabilities, 4, 512, [1.1], 0},
          {:probabilities, 4, 512, [0.1 | :invalid_tail], 0},
          {:transcript, "must not retain"},
          {:audio, %{frame() | tenant_id: :binary.copy("x", 257)}},
          {:audio, %{frame() | payload: <<1>>}}
        ] do
      assert {:error, :invalid_evidence} = CaptureHandoff.offer(handoff, invalid)
    end

    assert %{pending_count: 0} = CaptureHandoff.stats(handoff)
  end

  test "room completion IDs are detached and bounded before retention" do
    {:ok, handoff} = new_handoff()
    backing = :binary.copy("x", 100_000)
    id = binary_part(backing, 1, 128)
    generation = make_ref()
    reference = make_ref()

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:room_turn_completed, generation, reference, id, id, 0}
             )

    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message

    assert {:ok, {:room_turn_completed, ^generation, ^reference, turn, command, 0}, charge} =
             CaptureHandoff.message(handoff, message)

    assert :binary.referenced_byte_size(turn) == 128
    assert :binary.referenced_byte_size(command) == 128
    CaptureHandoff.release(handoff, charge, :processed)

    assert {:error, :invalid_evidence} =
             CaptureHandoff.offer(
               handoff,
               {:room_turn_completed, generation, reference, :binary.copy("x", 257), id, 0}
             )
  end

  defp new_handoff(options \\ []),
    do:
      CaptureHandoff.new(
        self(),
        Keyword.put(options, :settings, Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))
      )

  defp frame do
    %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 0,
      payload: :binary.copy(<<1, 0>>, 320),
      received_at: -10,
      source_epoch: make_ref()
    }
  end
end
