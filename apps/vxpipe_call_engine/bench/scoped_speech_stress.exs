# MIX_ENV=test mix run bench/scoped_speech_stress.exs /tmp/scoped-speech-stress.json
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.ScopedSpeechStressBench do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.SpeechExperiment.{Call, Recorder}
  alias Vxpipe.CallEngine.TestAudioOutputSink

  @path List.first(System.argv()) || Path.join(System.tmp_dir!(), "scoped-speech-stress.json")
  @maximum_concurrency max(1, div(System.schedulers_online(), 2))

  @tag timeout: 120_000
  @tag :capture_log
  test "permission commit and real PCM barge-in during other rooms' paced turns" do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    trials =
      for count <- [@maximum_concurrency] do
        healthy = for _ <- 1..count, do: Call.start(:scoped)
        blocked = Call.start(:scoped, block_output: true)
        policy = Call.start(:scoped)
        assert Call.turn(policy, :burst).valid_correlations?
        :ok = Recorder.begin_turn(blocked.recorder)
        :ok = Recorder.tail(blocked.recorder)
        Call.push(blocked, Call.pcm(60))
        {_, old_frame} = Recorder.await(blocked.recorder, :audio)
        :ok = TestAudioOutputSink.playback_started(blocked.sink)

        test = self()

        jobs =
          Enum.map(healthy, fn context ->
            Task.Supervisor.async_nolink(tasks, fn ->
              Call.turn(context, :paced,
                after_begin: fn ->
                  send(test, {:paced_turn_ready, self()})

                  receive do
                    :start_paced_turn -> :ok
                  end
                end
              )
            end)
          end)

        Enum.each(jobs, fn task ->
          pid = task.pid
          assert_receive {:paced_turn_ready, ^pid}, 5_000
        end)

        Enum.each(jobs, &send(&1.pid, :start_paced_turn))
        Enum.each(healthy, &Recorder.await(&1.recorder, :started))

        Enum.each(healthy, fn context ->
          refute Map.has_key?(Recorder.snapshot(context.recorder).counts, :completed)
        end)

        <<dot::binary-size(1_920), gap::binary>> = Call.pcm(60)
        onset = now()
        Call.push(blocked, dot)
        {interrupted_at, interrupted} = Recorder.await(blocked.recorder, :interrupted)
        {sink_at, _} = Recorder.await(blocked.recorder, :sink_interrupt)
        assert interrupted.correlation_id == old_frame.correlation_id
        assert sink_at <= interrupted_at
        assert Recorder.snapshot(blocked.recorder).counts.ended == 1

        policy_started = now()
        revoke(policy)
        policy_commit = now() - policy_started
        # These jobs are demonstrably still in flight during the control operations.
        Enum.each(healthy, fn context ->
          refute Map.has_key?(Recorder.snapshot(context.recorder).counts, :completed)
        end)

        :ok = GenServer.call(blocked.sink, {:block_output, false})
        :ok = Recorder.tail(blocked.recorder)
        Call.push(blocked, gap)
        replacement = Recorder.result(blocked.recorder)
        assert replacement.valid_correlations?
        assert replacement.output == Call.pcm(20)
        assert replacement.counts == %{started: 2, final: 2, ended: 2, text: 2, completed: 1}

        results = Enum.map(jobs, &Task.await(&1, 10_000))

        Enum.each(results, fn result ->
          assert result.valid_correlations?
          assert result.transcript == "E"
          assert result.output == Call.pcm(20)
          assert result.counts == %{started: 1, final: 1, ended: 1, text: 1, completed: 1}
        end)

        Enum.each([blocked, policy | healthy], &Call.stop/1)
        IO.puts("production native STT controls during #{count} paced rooms: pass")

        %{
          path: :production_native_stt,
          concurrency: count,
          healthy_turns: count,
          barge_in_sink_us: sink_at - onset,
          interruption_event_us: interrupted_at - onset,
          policy_commit_us: policy_commit,
          healthy_metrics: Enum.map(results, & &1.metrics)
        }
      end

    File.write!(
      @path,
      JSON.encode!(%{
        trials: trials,
        maximum_concurrency: @maximum_concurrency,
        semantics:
          "held output, PCM onset before gap, policy revoke, exact replacement PCM; local controlled sink"
      })
    )

    IO.puts("Stress report: #{@path}")
  end

  defp revoke(context) do
    capability = :sys.get_state(context.attachment.media_ingress).capability
    old = :sys.get_state(capability).session
    old_tree = Vxpipe.CallEngine.Speech.Session.tree(old)
    monitor = Process.monitor(old_tree)
    participant = Map.fetch!(context.plan.participants, "restrictor")

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: context.plan.tenant_id,
               actor_id: context.plan.actor_id,
               room_id: context.plan.room_id,
               participant_id: participant.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} = CallEngine.join_participant(join)
    assert_receive {:DOWN, ^monitor, :process, ^old_tree, _}, 1_000
    :ok = Recorder.begin_turn(context.recorder)
    Call.push(context, Call.pcm(60))
    _ = :sys.get_state(context.attachment.media_ingress)
    _ = :sys.get_state(capability)
    assert :sys.get_state(capability).session == nil
    assert Recorder.snapshot(context.recorder).counts == %{}
  end

  defp now, do: System.monotonic_time(:microsecond)
end
