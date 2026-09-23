defmodule Vxpipe.CallEngine.Media.STSIngressTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}

  @identity %{
    tenant_id: "sts-tenant",
    room_id: "sts-room",
    incarnation_id: "sts-incarnation",
    participant_id: "human",
    connection_id: "source"
  }
  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  test "starts closed and bounds queued frames independently of provider credit" do
    ingress = start_ingress(maximum_frames: 2, maximum_bytes: 4)
    assert {:ok, _, :preparing} = STSIngress.readiness(ingress)
    assert :ok = Enforcer.apply(ingress, policy(0), 500)
    assert :ok = STSIngress.prepare_track(ingress, @track)
    assert {:ok, resource, :ready} = STSIngress.readiness(ingress)
    assert :ok = STSIngress.push(ingress, frame(1))
    refute_received {:vxpipe_sts_input, _, _, _, _}
    assert :ok = STSIngress.open(ingress)
    assert :ok = STSIngress.push(ingress, frame(2))
    assert_receive {:vxpipe_sts_input, ^ingress, first, %AudioFrame{sequence_number: 2}, 0}
    assert :ok = STSIngress.push(ingress, frame(3))
    assert {:error, :queue_full} = STSIngress.push(ingress, frame(4))
    refute_received {:vxpipe_sts_input, _, _, _, _}

    acknowledge(ingress, first)
    assert_receive {:vxpipe_sts_input, ^ingress, second, %AudioFrame{sequence_number: 3}, 0}
    acknowledge(ingress, second)
    assert {:ok, ^resource, :ready} = STSIngress.readiness(ingress)
    assert %{queued: 0, in_flight?: false, dropped: 1} = STSIngress.stats(ingress)
  end

  test "revocation and hold fence queued input without granting a second outstanding credit" do
    ingress = ready_ingress()
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, first, _, 0}
    assert :ok = STSIngress.push(ingress, frame(2))
    denied = policy(1, %{})
    assert :ok = Enforcer.apply(ingress, denied, 500)
    assert {:error, :policy_denied} = STSIngress.push(ingress, frame(3))
    assert :ok = Enforcer.apply(ingress, policy(2), 500)
    assert :ok = STSIngress.push(ingress, frame(4))
    refute_received {:vxpipe_sts_input, _, _, _, _}

    acknowledge(ingress, first)
    assert_receive {:vxpipe_sts_input, ^ingress, second, %AudioFrame{sequence_number: 4}, 2}
    assert :ok = STSIngress.push(ingress, frame(5))
    assert :ok = STSIngress.hold(ingress)
    assert :ok = STSIngress.push(ingress, frame(6))
    acknowledge(ingress, second)
    assert :ok = STSIngress.open(ingress)
    refute_received {:vxpipe_sts_input, _, _, _, _}
    assert :ok = STSIngress.push(ingress, frame(7))
    assert_receive {:vxpipe_sts_input, ^ingress, _, %AudioFrame{sequence_number: 7}, 2}
  end

  test "activity boundaries wait behind accepted PCM and keep their input epoch" do
    ingress = ready_ingress()
    epoch = make_ref()
    assert :ok = STSIngress.open(ingress, epoch)
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, first, _, 0, ^epoch}

    intervals = %{input: 0, output: 0}
    assert :ok = STSIngress.activity(ingress, :started, epoch, intervals)
    assert :ok = STSIngress.activity(ingress, :ended, epoch, intervals)
    refute_received {:vxpipe_sts_activity, _, _, _, _, _}

    acknowledge(ingress, first)
    assert_receive {:vxpipe_sts_activity, ^ingress, started, :started, ^intervals, ^epoch}
    refute_received {:vxpipe_sts_activity, _, _, :ended, _, _}

    send(ingress, {:vxpipe_sts_activity_result, self(), started, :ok})
    assert_receive {:vxpipe_sts_activity, ^ingress, ended, :ended, ^intervals, ^epoch}
    send(ingress, {:vxpipe_sts_activity_result, self(), ended, :ok})
    assert %{queued: 0, in_flight?: false} = STSIngress.stats(ingress)
  end

  test "hold and policy changes retire queued activity before delivery" do
    ingress = ready_ingress()
    epoch = make_ref()
    assert :ok = STSIngress.open(ingress, epoch)
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, first, _, 0, ^epoch}
    intervals = %{input: 0, output: 0}
    assert :ok = STSIngress.activity(ingress, :ended, epoch, intervals)

    assert :ok = STSIngress.hold(ingress)
    acknowledge(ingress, first)
    refute_received {:vxpipe_sts_activity, _, _, _, _, _}
    assert %{dropped: 0} = STSIngress.stats(ingress)
    assert {:error, :held} = STSIngress.activity(ingress, :started, epoch, intervals)

    next_epoch = make_ref()
    assert :ok = STSIngress.open(ingress, next_epoch)
    assert {:error, :stale_epoch} = STSIngress.activity(ingress, :ended, epoch, intervals)
    assert :ok = STSIngress.push(ingress, frame(2))
    assert_receive {:vxpipe_sts_input, ^ingress, second, _, 0, ^next_epoch}
    assert :ok = STSIngress.activity(ingress, :ended, next_epoch, intervals)
    assert :ok = Enforcer.apply(ingress, policy(1, %{}), 500)
    acknowledge(ingress, second)
    refute_received {:vxpipe_sts_activity, _, _, _, _, _}

    assert {:error, :stale_policy} =
             STSIngress.activity(ingress, :ended, next_epoch, intervals)
  end

  test "rejected activity terminates the ingress instead of admitting later audio" do
    ingress = ready_ingress()
    epoch = make_ref()
    assert :ok = STSIngress.open(ingress, epoch)
    monitor = Process.monitor(ingress)
    intervals = %{input: 0, output: 0}
    assert :ok = STSIngress.activity(ingress, :ended, epoch, intervals)
    assert_receive {:vxpipe_sts_activity, ^ingress, reference, :ended, ^intervals, ^epoch}
    assert :ok = STSIngress.push(ingress, frame(1))
    send(ingress, {:vxpipe_sts_activity_result, self(), reference, {:error, :policy_denied, 0}})
    assert_receive {:DOWN, ^monitor, :process, ^ingress, :activity_rejected}, 1_000
    refute_received {:vxpipe_sts_input, _, _, _, _, _}
  end

  test "unrelated transcript policy changes preserve a queued audio-scoped boundary" do
    ingress = ready_ingress()
    epoch = make_ref()
    assert :ok = STSIngress.open(ingress, epoch)
    current = :sys.get_state(ingress).policy

    intervals = %{
      input: Snapshot.interval(current, :audio_input, @identity.participant_id),
      output: Snapshot.interval(current, :audio_output, @identity.participant_id)
    }

    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, first, _, 0, ^epoch}
    assert :ok = STSIngress.activity(ingress, :ended, epoch, intervals)

    unrelated = policy(1)
    unrelated = %{unrelated | effective: %{unrelated.effective | save_transcripts: true}}
    assert :ok = Enforcer.apply(ingress, unrelated, 500)
    revised = :sys.get_state(ingress).policy
    assert Snapshot.interval(revised, :audio_input, @identity.participant_id) == intervals.input
    assert Snapshot.interval(revised, :audio_output, @identity.participant_id) == intervals.output

    acknowledge(ingress, first)
    assert_receive {:vxpipe_sts_activity, ^ingress, reference, :ended, ^intervals, ^epoch}
    send(ingress, {:vxpipe_sts_activity_result, self(), reference, :ok})
    assert %{queued: 0, in_flight?: false} = STSIngress.stats(ingress)
  end

  test "malformed internal activity calls are rejected without ending the ingress" do
    ingress = ready_ingress()
    epoch = make_ref()
    assert :ok = STSIngress.open(ingress, epoch)

    assert {:error, :invalid_activity} =
             GenServer.call(ingress, {:activity, :started, epoch, %{}})

    assert %{queued: 0, in_flight?: false} = STSIngress.stats(ingress)
  end

  test "rejects wrong identity, format, track, stale age and duplicate sequences before delivery" do
    ingress = ready_ingress()

    for field <- Map.keys(@identity) do
      assert {:error, :wrong_connection} =
               STSIngress.push(ingress, Map.put(frame(1), field, "other"))
    end

    assert {:error, :wrong_track} = STSIngress.push(ingress, %{frame(1) | track_id: "other"})

    assert {:error, :unsupported_audio} =
             STSIngress.push(ingress, %{frame(1) | sample_rate: 24_000})

    assert {:error, :unsupported_audio} = STSIngress.push(ingress, %{frame(1) | payload: <<1>>})
    assert {:error, :stale_frame} = STSIngress.push(ingress, %{frame(1) | received_at: 0})
    refute_received {:vxpipe_sts_input, _, _, _, _}
    assert :ok = STSIngress.push(ingress, frame(2))
    assert_receive {:vxpipe_sts_input, ^ingress, _, _, _}
    assert {:error, :stale_sequence} = STSIngress.push(ingress, frame(2))
  end

  test "a stalled delivery terminates instead of retaining microphone audio indefinitely" do
    ingress = ready_ingress(delivery_timeout_ms: 25)
    monitor = Process.monitor(ingress)
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, _, _, _}
    assert_receive {:DOWN, ^monitor, :process, ^ingress, :input_timeout}, 1_000
  end

  test "source connection loss retires its ingress" do
    source = start_supervised!({Agent, fn -> nil end})
    ingress = start_ingress(source_connection: source)
    monitor = Process.monitor(ingress)
    stop_supervised!(Agent)
    assert_receive {:DOWN, ^monitor, :process, ^ingress, _}
  end

  test "invalid budgets and unsupported input formats fail before admission starts" do
    for override <- [
          [maximum_frames: 0],
          [maximum_bytes: -1],
          [maximum_age_ms: :infinity],
          [delivery_timeout_ms: 0],
          [delivery_timeout_ms: 5_001],
          [format: %{codec: :opus, sample_rate: 16_000, channels: 1}],
          [format: %{codec: :linear16, sample_rate: 0, channels: 1}],
          [format: %{codec: :linear16, sample_rate: 16_000, channels: 2}]
        ] do
      assert {:error, reason} = start_supervised({STSIngress, options(override)})
      assert inspect(reason) =~ "invalid_configuration"
    end
  end

  test "track preparation is format qualified and cannot rebind an allocated source" do
    ingress = start_ingress([])
    assert {:error, :not_prepared} = STSIngress.open(ingress)

    assert {:ok, %{codec: :linear16, sample_rate: 16_000, channels: 1}} =
             STSIngress.media_format(ingress)

    assert :ok = Enforcer.apply(ingress, policy(0), 500)
    assert {:error, :not_prepared} = STSIngress.open(ingress)

    assert {:error, :unsupported_audio} =
             STSIngress.prepare_track(ingress, %{@track | sample_rate: 24_000})

    assert :ok = STSIngress.prepare_track(ingress, @track)
    assert :ok = STSIngress.prepare_track(ingress, @track)

    assert {:error, :track_already_prepared} =
             STSIngress.prepare_track(ingress, %{@track | track_id: "replacement"})
  end

  test "queued audio expires while waiting for credit and never reaches the capability" do
    time = start_supervised!({Agent, fn -> 1_000 end})
    ingress = ready_ingress(clock: fn -> Agent.get(time, & &1) end)
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, first, _, _}
    assert :ok = STSIngress.push(ingress, frame(2))
    Agent.update(time, fn _ -> 1_101 end)
    acknowledge(ingress, first)
    assert %{queued: 0, total_bytes: 0, dropped: 1} = STSIngress.stats(ingress)
    refute_received {:vxpipe_sts_input, _, _, _, _}
  end

  test "byte budget includes outstanding audio and only the exact acknowledgement frees it" do
    other = start_supervised!({Agent, fn -> nil end})
    ingress = ready_ingress(maximum_frames: 10, maximum_bytes: 4)
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, first, _, _}
    assert :ok = STSIngress.push(ingress, frame(2))
    assert {:error, :queue_full} = STSIngress.push(ingress, frame(3))
    send(ingress, {:vxpipe_sts_input_result, other, first, :ok})
    send(ingress, {:vxpipe_sts_input_result, self(), make_ref(), :ok})
    assert %{queued: 1, in_flight?: true, total_bytes: 4} = STSIngress.stats(ingress)
    refute_received {:vxpipe_sts_input, _, _, _, _}
    acknowledge(ingress, first)
    assert_receive {:vxpipe_sts_input, ^ingress, second, _, _}
    send(ingress, {:vxpipe_sts_input_result, self(), second, {:error, :busy}})
    assert %{total_bytes: 0, in_flight?: false, dropped: 2} = STSIngress.stats(ingress)
    send(ingress, {:input_timeout, first})
    assert :ok = STSIngress.push(ingress, frame(4))
    assert_receive {:vxpipe_sts_input, ^ingress, _, %AudioFrame{sequence_number: 4}, _}
  end

  test "membership and ordered policy acknowledgements are required even for unrestricted routes" do
    ingress = ready_ingress()
    missing_agent = %{policy(1) | present_participant_ids: MapSet.new(["human"])}
    assert :ok = Enforcer.apply(ingress, missing_agent, 500)
    assert {:error, :policy_denied} = STSIngress.push(ingress, frame(1))
    assert {:ok, _, :preparing} = STSIngress.readiness(ingress)
    assert {:error, :stale_policy_revision} = Enforcer.apply(ingress, policy(0), 500)
    assert {:error, :unexpected_policy_revision} = Enforcer.apply(ingress, policy(3), 500)
    assert {:error, :policy_denied} = STSIngress.push(ingress, frame(2))
    assert :ok = Enforcer.apply(ingress, policy(2), 500)
    assert :ok = STSIngress.push(ingress, frame(3))
    assert_receive {:vxpipe_sts_input, ^ingress, _, _, 2}
  end

  test "capability loss retires its ingress without replaying queued input" do
    capability = start_supervised!({Agent, fn -> nil end})
    ingress = start_ingress(capability: capability)
    monitor = Process.monitor(ingress)
    stop_supervised!(Agent)
    assert_receive {:DOWN, ^monitor, :process, ^ingress, :normal}
    assert {:error, :unavailable} = STSIngress.open(ingress)
  end

  test "process status does not expose queued microphone audio" do
    ingress = ready_ingress()
    assert :ok = STSIngress.push(ingress, frame(1))
    assert_receive {:vxpipe_sts_input, ^ingress, _, _, _}
    private_audio = String.duplicate("private-mic", 2)
    assert :ok = STSIngress.push(ingress, %{frame(2) | payload: private_audio})
    refute inspect(:sys.get_status(ingress), limit: :infinity) =~ private_audio
  end

  defp ready_ingress(options \\ []) do
    ingress = start_ingress(options)
    assert :ok = Enforcer.apply(ingress, policy(0), 500)
    assert :ok = STSIngress.prepare_track(ingress, @track)
    assert :ok = STSIngress.open(ingress)
    ingress
  end

  defp start_ingress(overrides), do: start_supervised!({STSIngress, options(overrides)})

  defp options(overrides) do
    Keyword.merge(
      [
        capability: self(),
        source_connection: self(),
        identity: @identity,
        agent_id: "agent",
        format: Map.drop(@track, [:track_id]),
        maximum_age_ms: 100,
        clock: fn -> 1_000 end
      ],
      overrides
    )
  end

  defp frame(sequence) do
    struct!(
      AudioFrame,
      Map.merge(
        @identity,
        Map.merge(@track, %{
          sequence_number: sequence,
          timestamp: sequence * 320,
          payload: <<0, 0>>,
          received_at: 1_000
        })
      )
    )
  end

  defp acknowledge(ingress, reference),
    do: send(ingress, {:vxpipe_sts_input_result, self(), reference, :ok})

  defp policy(revision, routes \\ :unrestricted) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["human", "agent"]),
      effective: %Effective{
        audio_routes: routes,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }
  end
end
