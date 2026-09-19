defmodule Vxpipe.CallEngine.Speech.ScopedExperimentTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT
  alias Vxpipe.CallEngine.SpeechExperiment.Scope
  alias Vxpipe.CallEngine.SpeechExperiment.{Control, Worker}

  test "TTS rejects synthesis before readiness and readiness observed after deadline is rejected" do
    scope = start_supervised!({Scope, name: __MODULE__.Scope})
    {:ok, config} = MorseCodeSTT.new([])

    assert {:ok, control} =
             Scope.start_session(scope,
               owner: self(),
               kind: :tts,
               config: config,
               observer: self(),
               hold_start: true,
               deadline: System.monotonic_time(:millisecond) + 100
             )

    assert_receive {:experiment_held, worker}, 1_000

    assert {:error, :not_ready} =
             GenServer.call(
               control,
               {:control, JSON.encode!(%{"type" => "Speak", "text" => "E"})}
             )

    monitor = Process.monitor(control)
    :ok = :sys.suspend(control)
    send(worker, :release_start)
    _ = :sys.get_state(worker)
    token = make_ref()
    Process.send_after(self(), {:deadline_passed, token}, 120)
    assert_receive {:deadline_passed, ^token}, 1_000
    :ok = :sys.resume(control)
    assert_receive {:DOWN, ^monitor, :process, ^control, _}, 1_000
    refute_received {:experiment_observed, ^control, :ready, _}
  end

  test "owner loss removes every allocation descendant while another allocation stays usable" do
    scope = start_supervised!({Scope, name: __MODULE__.Scope})
    owner = start_supervised!({Agent, fn -> :owner end})
    {:ok, config} = MorseCodeSTT.new([])

    assert {:ok, control} =
             Scope.start_session(scope,
               owner: owner,
               kind: :stt,
               config: config,
               observer: self(),
               hold_start: true
             )

    assert_receive {:experiment_held, worker}, 1_000
    [{_, tree, :supervisor, _}] = DynamicSupervisor.which_children(scope)
    monitors = Enum.map([control, worker, tree], &{&1, Process.monitor(&1)})
    stop_supervised!(Agent)

    for {pid, monitor} <- monitors,
        do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 1_000)

    assert {:ok, healthy} = Scope.start_session(scope, owner: self(), kind: :stt, config: config)
    assert_receive {:vxpipe_stt_transport, ^healthy, {:message, _}}, 1_000
    assert :ok = GenServer.call(healthy, {:audio, reference_e()})
  end

  test "failed output credit retires the allocation instead of leaving a silent request" do
    scope = start_supervised!({Scope, name: __MODULE__.Scope})
    {:ok, config} = MorseCodeSTT.new([])

    assert {:ok, control} =
             Scope.start_session(scope,
               owner: self(),
               kind: :tts,
               config: config,
               observer: self()
             )

    assert_receive {:experiment_observed, ^control, :ready, _}, 1_000
    speak(control)
    assert_receive {:vxpipe_tts_transport, ^control, {:audio, credit, _}}, 1_000
    monitor = Process.monitor(control)
    send(control, {:vxpipe_tts_audio_result, self(), credit, {:error, :closed}})
    assert_receive {:DOWN, ^monitor, :process, ^control, _}, 1_000
  end

  test "expired admission creates no allocation and startup expiry removes a held worker" do
    scope = start_supervised!({Scope, name: __MODULE__.Scope})
    {:ok, config} = MorseCodeSTT.new([])
    options = [owner: self(), kind: :stt, config: config, observer: self()]

    assert {:error, :expired} =
             Scope.start_session(
               scope,
               Keyword.put(options, :deadline, System.monotonic_time(:millisecond) - 1)
             )

    assert DynamicSupervisor.count_children(scope).active == 0

    assert {:ok, control} =
             Scope.start_session(
               scope,
               options ++ [hold_start: true, deadline: System.monotonic_time(:millisecond) + 100]
             )

    assert_receive {:experiment_held, worker}, 1_000
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    refute_received {:vxpipe_stt_transport, ^control, {:message, _}}
  end

  test "one output credit bounds audio and cancelled generation cannot contaminate its replacement" do
    scope = start_supervised!({Scope, name: __MODULE__.Scope})
    {:ok, config} = MorseCodeSTT.new(unit_duration_ms: 20)

    assert {:ok, control} =
             Scope.start_session(scope,
               owner: self(),
               kind: :tts,
               config: config,
               observer: self()
             )

    assert_receive {:experiment_observed, ^control, :ready, _}, 1_000
    speak(control)
    assert_receive {:vxpipe_tts_transport, ^control, {:control, _started}}, 1_000
    assert_receive {:vxpipe_tts_transport, ^control, {:audio, old_credit, _audio}}, 1_000
    token = GenServer.call(control, :inspect_scope)
    _ = :sys.get_state(Worker.address(token))
    _ = :sys.get_state(Control.address(token))
    refute_received {:vxpipe_tts_transport, ^control, {:audio, _, _}}
    refute_received {:vxpipe_tts_transport, ^control, {:control, _}}

    assert :ok =
             GenServer.call(
               control,
               {:control, JSON.encode!(%{"type" => "Interrupt", "playback_offset_ms" => 0})}
             )

    assert_receive {:vxpipe_tts_transport, ^control, {:control, cancelled}}, 1_000
    assert %{"type" => "SpeechInterrupted"} = JSON.decode!(cancelled)
    send(control, {:semantic, {:tts, 1, {:audio, <<1, 2>>}}})
    send(control, {:vxpipe_tts_audio_result, self(), old_credit, :ok})
    speak(control)
    assert_receive {:vxpipe_tts_transport, ^control, {:control, _started}}, 1_000
    assert collect_audio(control, []) == Vxpipe.CallEngine.SpeechExperiment.Call.pcm(20)
    assert :ok = GenServer.call(control, :close)
  end

  test "held initialization leaves a sibling ready and decoding before release" do
    scope = start_supervised!({Scope, name: __MODULE__.Scope})
    {:ok, config} = MorseCodeSTT.new([])

    options = [owner: self(), kind: :stt, config: config, observer: self()]
    assert {:ok, held} = Scope.start_session(scope, Keyword.put(options, :hold_start, true))
    assert_receive {:experiment_held, worker}, 1_000
    assert {:ok, healthy} = Scope.start_session(scope, options)
    assert_receive {:vxpipe_stt_transport, ^healthy, {:message, ready}}, 1_000
    assert %{"type" => "Connected"} = JSON.decode!(ready)

    assert :ok = GenServer.call(healthy, {:audio, reference_e()})
    assert_receive {:vxpipe_stt_transport, ^healthy, {:message, started}}, 1_000
    assert %{"event" => "StartOfTurn"} = JSON.decode!(started)
    assert_receive {:vxpipe_stt_transport, ^healthy, {:message, partial}}, 1_000
    assert %{"event" => "Update", "transcript" => "E"} = JSON.decode!(partial)
    assert_receive {:vxpipe_stt_transport, ^healthy, {:message, ended}}, 1_000
    assert %{"event" => "EndOfTurn", "transcript" => "E"} = JSON.decode!(ended)
    refute_received {:vxpipe_stt_transport, ^held, {:message, _}}

    monitor = Process.monitor(worker)
    assert :ok = GenServer.call(held, :close)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  # Independently constructed E: one 60ms sinusoidal dot and fourteen silence units.
  defp reference_e do
    dot =
      for sample <- 0..959, into: <<>> do
        value = round(:math.sin(2 * :math.pi() * 700 * sample / 16_000) * 4_096)
        <<value::little-signed-16>>
      end

    dot <> :binary.copy(<<0, 0>>, 13_440)
  end

  defp speak(control) do
    assert :ok =
             GenServer.call(
               control,
               {:control, JSON.encode!(%{"type" => "Speak", "text" => "E"})}
             )

    assert :ok = GenServer.call(control, {:control, JSON.encode!(%{"type" => "Flush"})})
  end

  defp collect_audio(control, chunks) do
    receive do
      {:vxpipe_tts_transport, ^control, {:audio, credit, audio}} ->
        send(control, {:vxpipe_tts_audio_result, self(), credit, :ok})
        collect_audio(control, [audio | chunks])

      {:vxpipe_tts_transport, ^control, {:control, payload}} ->
        assert %{"type" => "SpeechMetadata"} = JSON.decode!(payload)
        chunks |> Enum.reverse() |> IO.iodata_to_binary()
    after
      1_000 -> flunk("missing TTS terminal")
    end
  end
end
