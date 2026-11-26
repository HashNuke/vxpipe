defmodule Vxpipe.CallEngine.RoomMixer.RecordingSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.RoomMixer.RecordingSelection

  @identity %{
    tenant_id: "tenant-selection",
    room_id: "room-selection",
    incarnation_id: "incarnation-selection"
  }

  test "room-origin same payload keeps first accepted regardless of admission order" do
    order = %{"conn-a" => 0, "conn-b" => 1}

    first = frame("alice", "conn-a", 0, :room, <<1, 2, 3, 4>>)
    second = frame("alice", "conn-b", 0, :room, <<1, 2, 3, 4>>)

    assert {:keep_first, 1, "conn-a"} =
             RecordingSelection.resolve(first, second, order)

    # reversed arrival: conn-b arrives first, conn-a second, same payload
    assert {:keep_first, 1, "conn-b"} =
             RecordingSelection.resolve(second, first, order)
  end

  test "room-origin different payload chooses newest admitted listener within slot" do
    order = %{"conn-a" => 0, "conn-b" => 1}

    first = frame("alice", "conn-a", 0, :room, <<1, 2, 3, 4>>)
    second = frame("alice", "conn-b", 0, :room, <<5, 6, 7, 8>>)

    # conn-a first, conn-b second, payloads differ -> newest admitted (conn-b) wins
    assert {:replace, 1, "conn-b"} =
             RecordingSelection.resolve(first, second, order)

    # reversed arrival: conn-b first, conn-a second, payloads differ -> still newest (conn-b)
    assert {:keep_first, 1, "conn-b"} =
             RecordingSelection.resolve(second, first, order)
  end

  test "reusing a listener id does not change the rank of buffered audio" do
    old_a = %{frame("caller", "a", 0, :room, <<1, 1>>) | recording_equivalent_max_order: 0}
    b = frame("caller", "b", 0, :room, <<2, 2>>)
    order = %{"a" => 2, "b" => 1}
    assert {:replace, 1, "b"} = RecordingSelection.resolve(old_a, b, order)

    assert {:replace, 1, "a"} =
             RecordingSelection.resolve(b, %{old_a | recording_equivalent_max_order: 2}, order)
  end

  test "agent-origin same payload keeps first accepted regardless of listener order" do
    order = %{"listener-1" => 0, "listener-2" => 1}

    first = frame("agent-1", "listener-1", 10, :participant, <<9, 9, 9, 9>>)
    second = frame("agent-1", "listener-2", 10, :participant, <<9, 9, 9, 9>>)

    assert {:keep_first, 1, "listener-1"} =
             RecordingSelection.resolve(first, second, order)

    assert {:keep_first, 1, "listener-2"} =
             RecordingSelection.resolve(second, first, order)
  end

  test "agent-origin different payload chooses newest admitted listener" do
    order = %{"listener-1" => 0, "listener-2" => 1}

    first = frame("agent-1", "listener-1", 10, :participant, <<1, 1, 1, 1>>)
    second = frame("agent-1", "listener-2", 10, :participant, <<2, 2, 2, 2>>)

    assert {:replace, 1, "listener-2"} =
             RecordingSelection.resolve(first, second, order)

    assert {:keep_first, 1, "listener-2"} =
             RecordingSelection.resolve(second, first, order)
  end

  test "two human simultaneous connection tracks do not deduplicate" do
    order = %{"conn-a" => 0, "conn-b" => 1}

    first = %{frame("alice", "conn-a", 0, :participant, <<1, 2, 3, 4>>) | track_id: "input"}
    second = %{frame("alice", "conn-b", 0, :participant, <<1, 2, 3, 4>>) | track_id: "input"}

    assert :distinct = RecordingSelection.resolve(first, second, order)
    assert :distinct = RecordingSelection.resolve(second, first, order)

    different = %{second | payload: <<5, 6, 7, 8>>}
    assert :distinct = RecordingSelection.resolve(first, different, order)
  end

  test "different sources at same timestamp do not deduplicate" do
    order = %{"conn-a" => 0, "conn-b" => 1}

    first = frame("agent-1", "conn-a", 10, :participant, <<1, 2, 3, 4>>)
    second = frame("agent-2", "conn-b", 10, :participant, <<1, 2, 3, 4>>)

    assert :distinct = RecordingSelection.resolve(first, second, order)
  end

  test "room and agent at same timestamp do not deduplicate" do
    order = %{"conn-a" => 0, "conn-b" => 1}

    room = frame("alice", "conn-a", 10, :room, <<1, 2, 3, 4>>)
    agent = frame("agent-1", "conn-b", 10, :participant, <<1, 2, 3, 4>>)

    assert :distinct = RecordingSelection.resolve(room, agent, order)
  end

  test "stable agent mode does not depend on listener" do
    assert RecordingSelection.stable_agent_mode("agent-1") ==
             {:individual_track, "agent-1", "agent-1", "agent-egress"}

    assert RecordingSelection.stable_agent_mode("agent-1") ==
             RecordingSelection.stable_agent_mode("agent-1")
  end

  test "tri-listener oldest X newest identical X middle Y always selects X" do
    order = %{"conn-a" => 0, "conn-b" => 1, "conn-c" => 2}
    payload_x = <<1, 2, 3, 4>>
    payload_y = <<5, 6, 7, 8>>

    oldest_x = frame("alice", "conn-a", 0, :room, payload_x)
    middle_y = frame("alice", "conn-b", 0, :room, payload_y)
    newest_x = frame("alice", "conn-c", 0, :room, payload_x)

    arrivals = [
      [oldest_x, newest_x, middle_y],
      [oldest_x, middle_y, newest_x],
      [middle_y, oldest_x, newest_x],
      [middle_y, newest_x, oldest_x],
      [newest_x, oldest_x, middle_y],
      [newest_x, middle_y, oldest_x]
    ]

    for arrival <- arrivals do
      {kept, duplicates} = apply_arrivals(arrival, order)

      assert kept.payload == payload_x,
             "arrival #{inspect(Enum.map(arrival, & &1.connection_id))} should select X"

      # Two duplicates were folded into one stored frame.
      assert duplicates == 2
      assert kept.recording_duplicate_frames == 2

      # The winning X payload always carries the newest X rank (2), while
      # the stored frame is one of the X arrivals (never the Y middle).
      assert kept.connection_id in ["conn-a", "conn-c"]
      assert kept.recording_selected_connection_id == kept.connection_id
      assert RecordingSelection.equivalent_max_order(kept, order) == 2
    end

    # The Astra case: oldest X, newest identical X, then middle Y must keep X.
    {kept, _} = apply_arrivals([oldest_x, newest_x, middle_y], order)
    assert kept.payload == payload_x
    assert kept.connection_id == "conn-a"
    assert kept.recording_selected_connection_id == "conn-a"
  end

  test "tri-listener all identical preserves first equivalent frame" do
    order = %{"conn-a" => 0, "conn-b" => 1, "conn-c" => 2}
    payload = <<9, 9, 9, 9>>

    a = frame("alice", "conn-a", 0, :room, payload)
    b = frame("alice", "conn-b", 0, :room, payload)
    c = frame("alice", "conn-c", 0, :room, payload)

    for arrival <- [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]] do
      {kept, duplicates} = apply_arrivals(arrival, order)
      [first | _] = arrival

      assert kept.payload == payload
      assert duplicates == 2
      assert kept.recording_duplicate_frames == 2
      assert kept.connection_id == first.connection_id
      assert kept.recording_selected_connection_id == first.connection_id
    end
  end

  test "equivalent max rank is tracked across identical arrivals" do
    order = %{"conn-a" => 0, "conn-b" => 1, "conn-c" => 2}
    payload_x = <<1, 1, 1, 1>>

    oldest = with_evidence(frame("alice", "conn-a", 0, :room, payload_x), order)
    newest = frame("alice", "conn-c", 0, :room, payload_x)

    assert RecordingSelection.equivalent_max_order(oldest, order) == 0

    tracked = RecordingSelection.track_equivalent(oldest, newest, order)
    assert tracked.connection_id == "conn-a"
    assert RecordingSelection.equivalent_max_order(tracked, order) == 2

    # A middle-rank different payload must not displace the X group once the
    # newest X rank is known.
    middle_y = frame("alice", "conn-b", 0, :room, <<2, 2, 2, 2>>)
    assert {:keep_first, 1, "conn-a"} = RecordingSelection.resolve(tracked, middle_y, order)
  end

  test "late duplicate timestamp stays bounded after flush" do
    alias Vxpipe.CallEngine.RoomMixer.TimestampBuffer

    buffer = TimestampBuffer.new(8)
    first = %{frame("alice", "conn-a", 0, :room, <<1, 2>>) | track_id: "t", sequence_number: 0}

    assert {:ok, buffer} = TimestampBuffer.put(buffer, first)
    assert {:ok, [{0, _bucket}], buffer} = TimestampBuffer.take_through(buffer, 0)

    late = %{first | connection_id: "conn-b"}

    assert {:error, :stale_timestamp} = TimestampBuffer.put(buffer, late)
    assert map_size(buffer.buckets) == 0
    assert buffer.last_flushed_timestamp == 0
  end

  defp frame(source, connection, timestamp, origin, payload) do
    %NormalizedFrame{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection,
      track_id: "agent-egress",
      sequence_number: 0,
      timestamp: timestamp,
      policy_revision: 0,
      sample_rate: 8_000,
      channels: 1,
      origin: origin,
      payload: payload
    }
  end

  defp with_evidence(frame, order) do
    %{
      frame
      | recording_duplicate_frames: 0,
        recording_selected_connection_id: frame.connection_id,
        recording_equivalent_max_order: Map.get(order, frame.connection_id, 0)
    }
  end

  # Mirrors RecordingEgress.dedupe_put folding for one timestamp group:
  # identical payloads preserve the first frame while tracking the highest
  # admission rank for that payload; different payloads compare against the
  # tracked best rank.
  defp apply_arrivals([first | rest], order) do
    kept = with_evidence(first, order)

    Enum.reduce(rest, {kept, 0}, fn incoming, {kept, duplicates} ->
      case RecordingSelection.resolve(kept, incoming, order) do
        {:keep_first, 1, selected} ->
          updated = %{
            kept
            | recording_duplicate_frames: duplicates + 1,
              recording_selected_connection_id: selected
          }

          updated =
            if kept.payload == incoming.payload do
              RecordingSelection.track_equivalent(updated, incoming, order)
            else
              updated
            end

          {updated, duplicates + 1}

        {:replace, 1, selected} ->
          incoming_order = Map.get(order, incoming.connection_id, 0)

          replaced = %{
            incoming
            | recording_duplicate_frames: duplicates + 1,
              recording_selected_connection_id: selected,
              recording_equivalent_max_order: incoming_order
          }

          {replaced, duplicates + 1}
      end
    end)
  end
end
