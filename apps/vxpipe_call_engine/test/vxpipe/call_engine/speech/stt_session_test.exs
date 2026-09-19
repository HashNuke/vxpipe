defmodule Vxpipe.CallEngine.Speech.STTSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionProbe

  @reference_runs [
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 3},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 3},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 7},
    {:tone, 1},
    {:silence, 1},
    {:tone, 1},
    {:silence, 1},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 1},
    {:tone, 3},
    {:silence, 14}
  ]

  test "independent odd-sized PCM becomes ordered typed transcript events" do
    session = start_supervised!({Session, provider: MorseSession, owner: self()})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    assert {:ok, config} = Config.new()

    config
    |> then(&reference_pcm(@reference_runs, &1))
    |> split_repeatedly([1, 319, 47, 641, 2_003])
    |> Enum.each(fn chunk -> assert :ok = Session.push_audio(session, chunk) end)

    events = receive_turn(session, [])
    assert Enum.map(events, & &1.sequence) == Enum.to_list(2..(length(events) + 1))
    assert Enum.count(events, &(&1.kind == :speech_started)) == 1
    assert %Event{kind: :turn_ended, text: "SOS 2", turn_ref: turn_ref} = List.last(events)
    assert is_reference(turn_ref)
    assert Enum.all?(events, &(&1.turn_ref == turn_ref and &1.generation == ready.generation))
    assert Enum.all?(events, &is_nil(&1.provider_request_id))

    assert Enum.map(Enum.filter(events, &(&1.kind == :transcript)), & &1.text) ==
             ["S", "SO", "SOS", "SOS 2"]

    monitor = Process.monitor(session)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^session, _reason}
  end

  test "configuration is closed, pure and truthful about local evidence" do
    for options <- [
          [auth: "private-value"],
          [endpoint: "https://invalid"],
          [:bad],
          :bad,
          [sample_rate: 44_100],
          [sample_rate: 8_000, sample_rate: 16_000]
        ] do
      assert {:error, :invalid_configuration} = MorseSession.configure(options)
    end

    for rate <- [8_000, 16_000, 24_000, 48_000] do
      assert {:ok, descriptor} = MorseSession.configure(sample_rate: rate)

      assert descriptor.format == %{
               encoding: :linear16,
               container: :raw,
               sample_rate: rate,
               channels: 1,
               byte_order: :little,
               signed?: true
             }

      assert descriptor.readiness == :initialized
      assert descriptor.endpointing == :provider_gap
      assert descriptor.usage_identity.provenance == :locally_measured
      assert descriptor.speech_start?
      refute descriptor.eager_end?
      refute descriptor.resume?
    end
  end

  test "rejects malformed, empty and oversized input without consuming audio" do
    session = start_supervised!({Session, provider: MorseSession})
    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(session, ready)
    assert {:error, :invalid_audio} = Session.push_audio(session, :bad)
    assert {:error, :invalid_audio_size} = Session.push_audio(session, <<>>)

    assert {:error, :invalid_audio_size} =
             Session.push_audio(session, :binary.copy(<<0>>, 131_073))

    assert :ok = Session.push_audio(session, <<0>>)
    assert :ok = Session.push_audio(session, <<0>>)
  end

  test "validates exact envelopes and delivers only one event until acknowledged" do
    session = start_supervised!({Session, provider: MorseSession})
    assert_receive {:vxpipe_speech, ready}
    assert {:ok, config} = Config.new()
    assert :ok = Session.push_audio(session, reference_pcm([{:tone, 1}, {:silence, 14}], config))
    refute_received {:vxpipe_speech, _event}
    assert {:error, :stale_event} = Session.ack(session, %{ready | generation: make_ref()})
    assert {:error, :stale_event} = Session.ack(session, %{ready | text: "forged"})
    assert :ok = Session.ack(session, ready)
    assert_receive {:vxpipe_speech, %Event{kind: :speech_started} = started}
    assert {:error, :stale_event} = Session.ack(session, ready)
    refute_received {:vxpipe_speech, _event}
    assert :ok = Session.ack(session, started)
    assert_receive {:vxpipe_speech, %Event{kind: :transcript} = transcript}
    assert :ok = Session.ack(session, transcript)
    assert_receive {:vxpipe_speech, %Event{kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
  end

  test "close discards an unfinished mark and is idempotent" do
    session = start_supervised!({Session, provider: MorseSession})
    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(session, ready)
    assert {:ok, config} = Config.new()
    assert :ok = Session.push_audio(session, reference_pcm([{:tone, 1}], config))
    assert_receive {:vxpipe_speech, %Event{kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    monitor = Process.monitor(session)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^session, _reason}
    assert :ok = Session.close(session)
    assert {:error, :closed} = Session.ack(session, started)
    refute_received {:vxpipe_speech, _event}
  end

  test "overflow is bounded and fails even when event credit is withheld" do
    session = start_supervised!({Session, provider: MorseSession})
    assert_receive {:vxpipe_speech, _ready}
    monitor = Process.monitor(session)
    assert {:ok, config} = Config.new()
    audio = reference_pcm([{:tone, 1}, {:silence, 14}], config)

    for _index <- 1..11, do: Session.push_audio(session, audio)

    assert_receive {:vxpipe_speech_closed, ^session, :event_overflow}
    assert_receive {:DOWN, ^monitor, :process, ^session, _reason}
    refute_received {:vxpipe_speech, _event}
  end

  test "owner loss tears down the session and provider" do
    owner = start_supervised!({Agent, fn -> :owner end})
    session = start_supervised!({Session, provider: MorseSession, owner: owner})
    [{_channel, metadata}] = Registry.lookup(Vxpipe.CallEngine.Speech.Registry, session)
    provider = metadata.provider
    session_monitor = Process.monitor(session)
    provider_monitor = Process.monitor(provider)
    assert {:error, :not_owner} = Session.push_audio(session, <<0, 0>>)
    Agent.stop(owner)
    assert_receive {:DOWN, ^session_monitor, :process, ^session, _reason}
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}
  end

  test "owner loss during held startup prevents early readiness and kills the provider" do
    owner = start_supervised!({Agent, fn -> :owner end})
    task_supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.StartupTasks})
    observer = self()

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Session.start(
          provider: SpeechSessionProbe,
          owner: owner,
          private: [observer: observer, hold_start?: true]
        )
      end)

    assert_receive {:probe_initializing, provider, {:via, Registry, {_registry, session}}}
    monitor = Process.monitor(provider)
    session_monitor = Process.monitor(session)
    refute_received {:vxpipe_speech, _event}
    Agent.stop(owner)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}
    assert_receive {:DOWN, ^session_monitor, :process, ^session, _reason}
    assert {:error, _safe_reason} = Task.await(task)
  end

  test "startup deadline also fences ready emitted from an unfinished init" do
    task_supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.DeadlineTasks})
    observer = self()

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Session.start(
          provider: SpeechSessionProbe,
          owner: observer,
          start_timeout: 100,
          private: [observer: observer, hold_start?: true]
        )
      end)

    assert_receive {:probe_initializing, provider, {:via, Registry, {_registry, _session}}}
    monitor = Process.monitor(provider)
    refute_received {:vxpipe_speech, _event}
    # Either the channel deadline or bounded OTP startup can win. Both must
    # discard early readiness, terminate the provider and return a safe failure.
    assert {:error, :initialization_failed} = Task.await(task, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}
    refute_received {:vxpipe_speech, _event}
  end

  test "input timeout retires the session before another submission can be admitted" do
    session =
      start_supervised!(
        {Session,
         provider: SpeechSessionProbe,
         call_timeout: 20,
         private: [observer: self(), trap_exits?: true, hold_input?: true]}
      )

    assert_receive {:probe_initializing, provider, _channel}
    on_exit(fn -> Process.exit(provider, :kill) end)
    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(session, ready)
    monitor = Process.monitor(provider)
    assert {:error, :session_failed} = Session.push_audio(session, <<0, 0>>)
    assert_receive {:probe_input, ^provider}
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}
    assert {:error, :closed} = Session.push_audio(session, <<0, 0>>)
    refute_received {:probe_input, _provider}
  end

  test "events and process status hide text, audio and crash messages" do
    session = start_supervised!({Session, provider: MorseSession})
    assert_receive {:vxpipe_speech, ready}
    assert :ok = Session.ack(session, ready)
    assert {:ok, config} = Config.new()
    assert :ok = Session.push_audio(session, reference_pcm(@reference_runs, config))
    events = receive_turn(session, [])
    ended = List.last(events)
    refute inspect(ended) =~ "SOS 2"
    [{channel, metadata}] = Registry.lookup(Vxpipe.CallEngine.Speech.Registry, session)
    refute inspect(:sys.get_status(metadata.provider)) =~ "SOS"
    refute inspect(:sys.get_status(channel)) =~ "SOS"

    sentinel = "private-audio-transcript-secret"
    status = %{state: sentinel, message: sentinel, reason: sentinel, log: [sentinel]}
    refute inspect(MorseSession.format_status(status)) =~ sentinel
    refute inspect(Vxpipe.CallEngine.Speech.Channel.format_status(status)) =~ sentinel
  end

  test "event fields cannot bypass the channel's size and type bounds" do
    channel = :no_channel_needed_for_rejected_events

    for fields <- [
          [readiness: :initialized, turn_ref: "not-an-opaque-reference"],
          [readiness: :initialized, reason: "private-provider-error"],
          [readiness: :initialized, endpointing: "unbounded"],
          [readiness: :initialized, text: :binary.copy("x", 4_097)],
          [readiness: :initialized, provider_request_id: :binary.copy("x", 257)]
        ] do
      assert {:error, :invalid_event} = Event.emit(channel, :ready, fields)
    end
  end

  test "only the bound provider can publish semantic events" do
    session = start_supervised!({Session, provider: MorseSession})
    channel = Vxpipe.CallEngine.Speech.Channel.address(session)
    assert {:error, :unbound_producer} = Event.emit(channel, :ready, readiness: :initialized)
  end

  test "explicit close during startup removes the held provider" do
    task_supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.CloseTasks})
    observer = self()

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Session.start(
          provider: SpeechSessionProbe,
          owner: observer,
          call_timeout: 20,
          private: [observer: observer, hold_start?: true]
        )
      end)

    assert_receive {:probe_initializing, provider, {:via, Registry, {_registry, session}}}
    monitor = Process.monitor(provider)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}
    assert {:error, _reason} = Task.await(task)
    refute_received {:vxpipe_speech, _event}
  end

  test "supervisor status and child failure logs do not retain private initialization" do
    sentinel = "private-init-regression-sentinel"
    session = start_supervised!({Session, provider: MorseSession, private: [api_key: sentinel]})

    refute inspect(:sys.get_status(session), limit: :infinity, printable_limit: :infinity) =~
             sentinel

    [{_channel, metadata}] = Registry.lookup(Vxpipe.CallEngine.Speech.Registry, session)
    monitor = Process.monitor(session)

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        Process.exit(metadata.provider, :provider_failed)
        assert_receive {:DOWN, ^monitor, :process, ^session, _reason}
      end)

    refute logs =~ sentinel
  end

  test "public startup errors do not expose provider responses" do
    result =
      Session.start(
        provider: SpeechSessionProbe,
        private: [observer: self(), start_error: {:upstream_response, "private-error-sentinel"}]
      )

    assert result == {:error, :initialization_failed}
  end

  test "owner loss before binding still bounds a provider that traps exits" do
    owner = start_supervised!({Agent, fn -> :owner end})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.BeforeBindTasks})
    observer = self()

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        Session.start(
          provider: SpeechSessionProbe,
          owner: owner,
          start_timeout: 100,
          private: [observer: observer, trap_exits?: true, hold_before_bind?: true]
        )
      end)

    assert_receive {:probe_before_bind, provider, _channel}
    on_exit(fn -> Process.exit(provider, :kill) end)
    monitor = Process.monitor(provider)
    Agent.stop(owner)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 1_000
    assert {:error, :initialization_failed} = Task.await(task)
  end

  defp receive_turn(session, events) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}
    assert :ok = Session.ack(session, event)

    if event.kind == :turn_ended,
      do: Enum.reverse([event | events]),
      else: receive_turn(session, [event | events])
  end

  defp reference_pcm(runs, config) do
    runs
    |> Enum.map(fn
      {:tone, units} -> reference_tone(units * unit_samples(config), config)
      {:silence, units} -> :binary.copy(<<0, 0>>, units * unit_samples(config))
    end)
    |> IO.iodata_to_binary()
  end

  defp reference_tone(sample_count, config) do
    period = div(config.sample_rate, config.frequency_hz)
    half_period = max(div(period, 2), 1)

    for sample_index <- 0..(sample_count - 1), into: <<>> do
      sample = if rem(div(sample_index, half_period), 2) == 0, do: 3_000, else: -3_000
      <<sample::signed-little-16>>
    end
  end

  defp split_repeatedly(binary, sizes), do: split_repeatedly(binary, sizes, sizes, [])

  defp split_repeatedly(<<>>, _remaining_sizes, _all_sizes, chunks),
    do: Enum.reverse(chunks)

  defp split_repeatedly(binary, [], all_sizes, chunks),
    do: split_repeatedly(binary, all_sizes, all_sizes, chunks)

  defp split_repeatedly(binary, [size | sizes], all_sizes, chunks)
       when byte_size(binary) > size do
    <<chunk::binary-size(size), rest::binary>> = binary
    split_repeatedly(rest, sizes, all_sizes, [chunk | chunks])
  end

  defp split_repeatedly(binary, _sizes, _all_sizes, chunks),
    do: Enum.reverse([binary | chunks])

  defp unit_samples(config), do: div(config.sample_rate * config.unit_duration_ms, 1_000)
end
