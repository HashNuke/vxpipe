defmodule Vxpipe.CallEngine.Speech.StartupIsolationTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, PrivateInit, Session}
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

    {:ok, held_session, :starting} =
      Session.start(scope(),
        provider: SpeechSessionProbe,
        owner: owner,
        private: [observer: owner, hold_start?: true]
      )

    assert_receive {:probe_initializing, held_provider, _channel}, 1_000
    jobs = start_morse_jobs(tasks)

    before_release =
      try do
        Task.yield_many(jobs, @observation_window)
      after
        send(held_provider, :release_start)
      end

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

    assert completed_before_release == @jobs

    assert Enum.all?(results, &(&1.start_ms <= @startup_budget)),
           "#{completed_before_release}/#{@jobs} healthy Morse sessions completed within " <>
             "#{@observation_window} ms while another session was held; each healthy session " <>
             "had a #{@startup_budget} ms startup budget. All decoded E after release."
  end

  test "a stalled Deepgram wire keeps an unrelated room's Morse recognition usable" do
    slow_command = command("slow")
    fast_command = command("fast")
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: slow_command.incarnation_id})
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: fast_command.incarnation_id})

    {provider, private} = deepgram_provider(before_connect: held_wire(self()))
    assert {:ok, _held_capability, _ingress} = start_native(slow_command, provider, private)
    assert_receive {:test_stt_wire_held, held_wire}, 1_000

    try do
      assert {:ok, capability, _ingress} = start_native(fast_command, MorseSession)
      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
      assert :ok = SpeechToText.push_audio(capability, frame(fast_command))

      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_ended, text: "E"}},
                     @observation_window
    after
      send(held_wire, :release_wire)
    end
  end

  test "a held native initializer leaves a same-room connection recognizing" do
    assert {:module, SpeechSessionProbe} = Code.ensure_loaded(SpeechSessionProbe)
    slow_command = command("native-slow")
    fast_command = peer_command(slow_command, "native-fast")
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: slow_command.incarnation_id})

    assert {:ok, _capability, _ingress} =
             start_native(slow_command, SpeechSessionProbe,
               observer: self(),
               hold_before_bind?: true
             )

    assert_receive {:probe_before_bind, held_provider, _channel}, 1_000

    try do
      assert {:ok, capability, _ingress} = start_native(fast_command, MorseSession)
      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
      assert :ok = SpeechToText.push_audio(capability, frame(fast_command))

      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_ended, text: "E"}},
                     @observation_window
    after
      send(held_provider, :release_bind)
    end
  end

  test "private initialization closes when its allocating owner exits before claim", %{
    tasks: tasks
  } do
    test = self()

    owner =
      Task.Supervisor.async_nolink(tasks, fn ->
        {:ok, handle} = PrivateInit.open([secret: "owner-loss-private-sentinel"], 5_000)
        send(test, {:private_init_opened, handle})

        receive do
          :stop_private_init_owner -> :ok
        end
      end)

    assert_receive {:private_init_opened, handle}, 1_000
    holder_monitor = Process.monitor(handle.pid)
    send(owner.pid, :stop_private_init_owner)
    assert :ok = Task.await(owner, 1_000)
    assert_receive {:DOWN, ^holder_monitor, :process, _holder, :normal}, 1_000
    assert {:error, :unavailable} = PrivateInit.claim(handle)
  end

  test "a held Deepgram initializer leaves a same-room Morse connection recognizing" do
    sentinel = "connection-tree-private-init-sentinel"
    slow_command = command("deepgram-slow")
    fast_command = peer_command(slow_command, "morse-fast")
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: slow_command.incarnation_id})

    {provider, private} =
      deepgram_provider(before_connect: held_wire(self()), private_header: sentinel)

    assert {:ok, held_capability, _ingress} =
             start_native(slow_command, provider, private)

    assert_receive {:test_stt_wire_held, held_wire}, 1_000
    held_tree = ConnectionTree.parent(held_capability)

    assert [{capability_supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:capability_supervisor, slow_command.incarnation_id}
             )

    for process <- [capability_supervisor, held_tree] do
      refute inspect(:sys.get_status(process), limit: :infinity, printable_limit: :infinity) =~
               sentinel
    end

    try do
      assert {:ok, capability, _ingress} = start_native(fast_command, MorseSession)
      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
      assert :ok = SpeechToText.push_audio(capability, frame(fast_command))

      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_ended, text: "E"}},
                     @observation_window

      monitor = Process.monitor(held_tree)

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Process.exit(held_capability, :kill)
          assert_receive {:DOWN, ^monitor, :process, ^held_tree, _reason}, 1_000
        end)

      refute logs =~ sentinel
    after
      send(held_wire, :release_wire)
    end
  end

  test "a held initializer leaves a same-scope sibling ready and recognizing", %{tasks: tasks} do
    scope = scope()

    {:ok, held, :starting} =
      Session.start(scope,
        provider: SpeechSessionProbe,
        private: [observer: self(), hold_start?: true]
      )

    assert_receive {:probe_initializing, provider, _channel}
    [job] = start_morse_jobs(tasks, [scope])

    try do
      result = Task.await(job, @observation_window)
      assert result.text == "E"
      assert result.start_ms <= @startup_budget
    after
      send(provider, :release_start)
      assert :ok = Session.close(held)
    end
  end

  defp scope do
    start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))
    |> CapabilityTree.scope()
  end

  defp start_morse_jobs(tasks), do: start_morse_jobs(tasks, for(_ <- 1..@jobs, do: scope()))

  defp start_morse_jobs(tasks, scopes) do
    observer = self()

    jobs =
      for scope <- scopes do
        Task.Supervisor.async_nolink(tasks, fn ->
          send(observer, {:morse_job_invoking, self()})
          started = System.monotonic_time(:millisecond)

          {:ok, session, :starting} =
            Session.start(scope, provider: MorseSession, start_timeout: @startup_budget)

          try do
            assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready},
                           1_000

            start_ms = System.monotonic_time(:millisecond) - started
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

  defp held_wire(observer) do
    fn ->
      send(observer, {:test_stt_wire_held, self()})

      receive do
        :release_wire -> :ok
      end
    end
  end

  defp deepgram_provider(wire_options) do
    {:ok, config} =
      Flux.new(
        api_key: "startup-isolation-fixture",
        model: "flux-general-en",
        encoding: :opus,
        sample_rate: 48_000
      )

    provider =
      {FluxSession,
       model: config.model, encoding: config.encoding, sample_rate: config.sample_rate}

    private = [
      config: config,
      wire_module: TestSpeechToTextTransport,
      wire_options: [observer: self()] ++ wire_options
    ]

    {provider, private}
  end

  defp start_native(command, provider, provider_private \\ [])

  defp start_native(command, provider, provider_private) when is_atom(provider),
    do: start_native(command, {provider, []}, provider_private)

  defp start_native(command, {provider, provider_options}, provider_private) do
    RoomCapabilitySupervisor.start_speech_to_text(
      command.incarnation_id,
      self(),
      command,
      {provider, provider_options},
      [
        maximum_age_ms: 1_000,
        maximum_bytes: 131_072,
        maximum_frames: 32,
        maximum_consecutive_overflows: 3
      ],
      nil,
      provider_private: provider_private
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

  defp peer_command(command, label) do
    suffix = System.unique_integer([:positive, :monotonic])

    {:ok, peer} =
      AttachConnection.new(
        tenant_id: command.tenant_id,
        actor_id: command.actor_id,
        room_id: command.room_id,
        incarnation_id: command.incarnation_id,
        participant_id: command.participant_id,
        connection_id: "conn-#{label}-#{suffix}",
        deadline: command.deadline
      )

    peer
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
