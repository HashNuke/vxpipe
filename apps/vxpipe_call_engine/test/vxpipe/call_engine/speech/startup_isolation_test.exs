defmodule Vxpipe.CallEngine.Speech.StartupIsolationTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Capability.SpeechToText.TransportConnector
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor
  alias Vxpipe.CallEngine.Speech.{Event, Session}
  alias Vxpipe.CallEngine.{SpeechSessionProbe, TestSpeechToTextTransport}

  @jobs 8
  @startup_budget 100
  @observation_window 300

  setup do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    {:ok, tasks: tasks}
  end

  test "eight independent Morse sessions start and recognize PCM without a stalled peer", %{
    tasks: tasks
  } do
    jobs = start_morse_jobs(tasks)
    results = Enum.map(jobs, &Task.await(&1, 2_000))
    report("unblocked", results)
    assert Enum.all?(results, &(&1.text == "E"))
    assert Enum.all?(results, &(&1.start_ms < @observation_window))
  end

  @tag :startup_isolation_regression
  test "a stalled semantic session must not consume unrelated sessions' startup budgets", %{
    tasks: tasks
  } do
    owner = self()

    held_start =
      Task.Supervisor.async_nolink(tasks, fn ->
        Session.start(
          provider: SpeechSessionProbe,
          owner: owner,
          private: [observer: owner, hold_start?: true]
        )
      end)

    assert_receive {:probe_initializing, held_provider, _channel}, 1_000
    jobs = start_morse_jobs(tasks)

    before_release =
      try do
        Task.yield_many(jobs, @observation_window)
      after
        send(held_provider, :release_start)
      end

    assert {:ok, held_session} = Task.await(held_start, 2_000)
    assert :ok = Session.close(held_session)

    results =
      Enum.map(before_release, fn
        {_task, {:ok, result}} -> result
        {task, nil} -> Task.await(task, 2_000)
      end)

    report("held peer, then released", results)
    assert Enum.all?(results, &(&1.text == "E"))

    completed_before_release =
      Enum.count(before_release, fn {_task, result} -> not is_nil(result) end)

    assert Enum.all?(results, &(&1.start_ms <= @startup_budget)),
           "#{completed_before_release}/#{@jobs} healthy Morse sessions completed within " <>
             "#{@observation_window} ms while another session was held; each healthy session " <>
             "had a #{@startup_budget} ms startup budget. All decoded E after release."
  end

  test "existing room startup keeps an unrelated room's Morse recognition usable", %{tasks: tasks} do
    owner = self()
    slow_command = command("slow")
    fast_command = command("fast")
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: slow_command.incarnation_id})
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: fast_command.incarnation_id})
    {:ok, config} = MorseCodeSTT.new([])

    slow_start =
      Task.Supervisor.async_nolink(tasks, fn ->
        start_legacy(
          slow_command,
          owner,
          config,
          {TestSpeechToTextTransport, observer: owner, before_connect: held_connection(owner)}
        )
      end)

    assert_receive {:legacy_start_held, held_capability}, 1_000

    try do
      fast_start =
        Task.Supervisor.async_nolink(tasks, fn ->
          start_legacy(fast_command, owner, config, {MorseCodeSTT.Transport, []})
        end)

      assert {:ok, capability, _ingress} = Task.await(fast_start, @observation_window)
      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
      assert :ok = SpeechToText.push_audio(capability, frame(fast_command))

      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_ended, text: "E"}},
                     @observation_window
    after
      send(held_capability, :release_connection)
      Task.await(slow_start, 2_000)
    end
  end

  test "existing replacement connector admits Morse while another connection is held" do
    # The real capability traps exits from linked connector tasks too.
    Process.flag(:trap_exit, true)
    {:ok, config} = MorseCodeSTT.new([])

    {:ok, slow} =
      TransportConnector.start(TestSpeechToTextTransport, %{},
        observer: self(),
        before_connect: held_connection(self())
      )

    assert_receive {:legacy_start_held, held_connector}, 1_000

    try do
      {:ok, fast} =
        TransportConnector.start(
          MorseCodeSTT.Transport,
          MorseCodeSTT.connection_options(config),
          []
        )

      connector = fast.pid
      assert_receive {:vxpipe_stt_connected, ^connector, transport}, @observation_window

      try do
        assert :ok = MorseCodeSTT.Transport.send_audio(transport, reference_e())
        assert "E" == receive_legacy_final(transport)
      after
        stop_connector(fast)
      end
    after
      send(held_connector, :release_connection)
      stop_connector(slow)
    end
  end

  defp start_morse_jobs(tasks) do
    observer = self()

    jobs =
      for _ <- 1..@jobs do
        Task.Supervisor.async_nolink(tasks, fn ->
          send(observer, {:morse_job_invoking, self()})
          started = System.monotonic_time(:millisecond)
          {:ok, session} = Session.start(provider: MorseSession, start_timeout: @startup_budget)
          start_ms = System.monotonic_time(:millisecond) - started

          try do
            assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready},
                           1_000

            assert :ok = Session.ack(session, ready)
            assert :ok = Session.push_audio(session, reference_e())
            %{text: receive_semantic_final(session), start_ms: start_ms}
          after
            Session.close(session)
          end
        end)
      end

    Enum.each(jobs, fn task ->
      pid = task.pid
      assert_receive {:morse_job_invoking, ^pid}, 1_000
    end)

    jobs
  end

  defp receive_semantic_final(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    if event.kind == :turn_ended, do: event.text, else: receive_semantic_final(session)
  end

  defp receive_legacy_final(transport) do
    assert_receive {:vxpipe_stt_transport, ^transport, {:message, payload}}, @observation_window
    assert {:ok, signal} = MorseCodeSTT.decode(payload)
    if signal.kind == :turn_ended, do: signal.text, else: receive_legacy_final(transport)
  end

  defp held_connection(observer) do
    fn ->
      send(observer, {:legacy_start_held, self()})

      receive do
        :release_connection -> :ok
      end
    end
  end

  defp stop_connector(connector) do
    pid = connector.pid
    monitor = Process.monitor(pid)
    :ok = TransportConnector.stop(connector)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
  end

  defp start_legacy(command, owner, config, transport) do
    RoomCapabilitySupervisor.start_speech_to_text(
      command.incarnation_id,
      owner,
      command,
      {MorseCodeSTT, config},
      transport,
      maximum_age_ms: 1_000,
      maximum_bytes: 131_072,
      maximum_frames: 32,
      maximum_consecutive_overflows: 3
    )
  end

  defp command(label) do
    suffix = System.unique_integer([:positive, :monotonic])

    {:ok, command} =
      AttachConnection.new(
        tenant_id: "tenant-test",
        actor_id: "test",
        room_id: "room-#{label}-#{suffix}",
        incarnation_id: "rinc-#{suffix}",
        participant_id: "human-#{suffix}",
        connection_id: "conn-#{suffix}",
        deadline: DateTime.add(DateTime.utc_now(), 60, :second)
      )

    command
  end

  defp frame(command) do
    %AudioFrame{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      track_id: "morse",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 320,
      payload: reference_e(),
      received_at: System.monotonic_time(:millisecond)
    }
  end

  # Independently generated dot and 14-unit end gap at the default 16 kHz.
  # No project Morse encoder supplies the expected transcript.
  defp reference_e do
    dot =
      for i <- 0..959, into: <<>> do
        sample = if rem(div(i, 11), 2) == 0, do: 3_000, else: -3_000
        <<sample::signed-little-16>>
      end

    dot <> :binary.copy(<<0, 0>>, 14 * 960)
  end

  defp report(label, results) do
    times = Enum.map(results, & &1.start_ms)

    IO.puts(
      "Morse startup (#{label}): #{@jobs} jobs, start latency #{Enum.min(times)}..#{Enum.max(times)} ms"
    )
  end
end
