defmodule Vxpipe.Providers.Deepgram.CloseStreamProbeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.TestFluxCloseProbe, as: Probe

  @moduletag :tmp_dir
  @tail "synthetic final tail."

  setup %{tmp_dir: directory} do
    path = Path.join(directory, "synthetic.pcm")
    File.write!(path, :binary.copy(<<0, 1>>, 3_000))
    Process.put(:probe_clock, 0)
    Process.put(:probe_frames, [])

    %{options: [enabled: true, fixture_path: path, expected_tail: @tail, timeout_ms: 100]}
  end

  test "socket child specification redacts startup inputs while preserving exact private delivery" do
    options = [
      connection: %{
        url: "wss://synthetic-private.invalid",
        headers: [{"Authorization", "synthetic-key"}]
      }
    ]

    callback = Probe.callback_state(self(), make_ref())

    assert :verified ==
             Probe.start_socket(options, callback, fn specification ->
               refute inspect(specification, limit: :infinity) =~ "synthetic-key"
               refute inspect(specification, limit: :infinity) =~ "synthetic-private"
               assert {Probe, :start_link, [private]} = specification.start
               assert {:ok, [options: ^options, callback: ^callback]} = PrivateInit.claim(private)
               :verified
             end)
  end

  test "failed socket startup retires its private handoff" do
    assert {:error, :synthetic} ==
             Probe.start_socket([], Probe.callback_state(self(), make_ref()), fn specification ->
               {Probe, :start_link, [private]} = specification.start
               monitor = Process.monitor(private.pid)
               send(self(), {:private_monitor, private.pid, monitor})
               {:error, :synthetic}
             end)

    assert_received {:private_monitor, pid, monitor}
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
  end

  test "explicit opt-in precedes credential, fixture and connector work", %{options: options} do
    hooks = hooks()

    for enabled <- [false, nil, "1"] do
      result =
        Probe.run(Keyword.merge(options, enabled: enabled, fixture_path: "/missing"), hooks)

      assert result.terminal == :not_armed
      refute result.passed?
    end

    refute_received :credential_resolved
    refute_received :connector_called
    assert Process.get(:probe_frames) == []
  end

  test "sends all bounded PCM in order then one CloseStream, retaining only a safe report",
       context do
    result = Probe.run(context.options, hooks())
    assert result.passed?
    assert result.terminal == :normal_or_no_status
    assert result.connected? and result.audio_sent? and result.close_stream_sent?
    assert result.tail_verified? and result.error_free?
    assert_received :credential_resolved
    assert_received :connector_called
    assert_received :cleanup_called

    frames = Enum.reverse(Process.get(:probe_frames))
    assert {:text, ~s({"type":"CloseStream"})} == List.last(frames)
    audio = Enum.drop(frames, -1)
    assert Enum.all?(audio, fn {:binary, bytes} -> byte_size(bytes) <= 2_560 end)

    assert IO.iodata_to_binary(Enum.map(audio, &elem(&1, 1))) ==
             File.read!(Keyword.fetch!(context.options, :fixture_path))

    assert map_size(result) == 7
    assert Enum.all?(result, fn {key, value} -> key == :terminal or is_boolean(value) end)
    refute inspect(result) =~ @tail
  end

  test "caught-up tail before CloseStream needs no new update afterward", context do
    hooks = hooks(before_finish: [turn(1, @tail)], after_finish: [:normal_close])
    assert Probe.run(context.options, hooks).passed?
  end

  test "multiple updates replace per-turn text and preserve separate turns", context do
    events = [
      turn(1, "wrong"),
      turn(2, "synthetic", "EndOfTurn"),
      turn(3, "final tail.", "Update", 1),
      :normal_close
    ]

    assert Probe.run(context.options, hooks(after_finish: events)).passed?
  end

  test "a matched earlier update cannot hide a later correction", context do
    result =
      Probe.run(
        context.options,
        hooks(after_finish: [turn(1, @tail), turn(2, "different"), :normal_close])
      )

    refute result.passed?
    refute result.tail_verified?
    assert result.terminal == :normal_or_no_status
  end

  for {name, events, terminal} <- [
        {"EOF", [:disconnect], :connection_lost},
        {"abnormal peer close", [{:close, 1_008}], :abnormal_peer_close},
        {"decode error", ["not JSON", :normal_close], :invalid_wire},
        {"provider error",
         [
           %{
             "type" => "Error",
             "sequence_id" => 1,
             "code" => "SYNTHETIC",
             "description" => "private reason"
           },
           :normal_close
         ], :provider_error},
        {"unknown wire", [%{"type" => "Unknown"}, :normal_close], :invalid_wire},
        {"missing tail", [:normal_close], :normal_or_no_status},
        {"EndOfTurn only", [:end_only], :timeout}
      ] do
    test "#{name} cannot prove successful flush", context do
      result = Probe.run(context.options, hooks(after_finish: unquote(Macro.escape(events))))
      refute result.passed?
      assert result.terminal == unquote(terminal)
    end
  end

  test "valid Connected is required before sending any input", context do
    result = Probe.run(context.options, hooks(initial: [turn(1, @tail)]))
    assert result.terminal == :invalid_order
    assert Process.get(:probe_frames) == []
  end

  test "missing Connected times out without sending input", context do
    result = Probe.run(context.options, hooks(initial: []))
    assert result.terminal == :timeout
    assert Process.get(:probe_frames) == []
  end

  test "duplicate Connected, wrong request and sequence regression are rejected", context do
    for event <- [connected(), Map.put(turn(1, @tail), "request_id", "other"), turn(0, @tail)] do
      result = Probe.run(context.options, hooks(after_finish: [event, :normal_close]))
      refute result.passed?
      assert result.terminal == :invalid_order
    end
  end

  test "peer close observed before finish is not promoted by later mailbox processing", context do
    result =
      Probe.run(
        context.options,
        hooks(before_finish: [turn(1, @tail), :normal_close], after_finish: [])
      )

    assert result.terminal == :early_peer_close
    refute result.passed?
  end

  test "failed PCM or CloseStream send cannot be repaired by queued success", context do
    for fail <- [:binary, :text] do
      result = Probe.run(context.options, hooks(fail_send: fail))
      assert result.terminal == :send_failed
      refute result.passed?
    end
  end

  test "terminal queued first but processed at or after deadline is timeout", context do
    for now <- [100, 101] do
      Process.put(:probe_clock, 0)

      result =
        Probe.run(
          context.options,
          hooks(after_finish: [turn(1, @tail), :normal_close, {:clock, now}])
        )

      assert result.terminal == :timeout
      refute result.passed?
    end
  end

  test "the same evidence strictly before expiry is accepted", context do
    assert Probe.run(
             context.options,
             hooks(after_finish: [turn(1, @tail), :normal_close, {:clock, 99}])
           ).passed?
  end

  test "connection time consumes the same absolute budget", context do
    result = Probe.run(context.options, hooks(initial: [connected(), {:clock, 100}]))
    assert result.terminal == :timeout
    assert Process.get(:probe_frames) == []
  end

  test "local process exit is not peer close", context do
    agent = start_supervised!({Agent, fn -> :fixture end})
    hooks = hooks()

    hooks =
      Map.put(hooks, :connect, fn _, _ ->
        :ok = stop_supervised(Agent)
        {:ok, agent}
      end)

    assert Probe.run(context.options, hooks).terminal == :local_teardown
  end

  test "invalid fixture and expected tail fail before credentials and connection", %{
    options: options
  } do
    for override <- [
          [fixture_path: "/missing"],
          [fixture_path: Path.dirname(Keyword.fetch!(options, :fixture_path))],
          [expected_tail: ""],
          [expected_tail: <<255>>],
          [expected_tail: String.duplicate("x", 257)],
          [timeout_ms: 30_001],
          [timeout_ms: 0]
        ] do
      assert Probe.run(Keyword.merge(options, override), hooks()).terminal == :invalid_input
    end

    for pcm <- [<<>>, <<1>>, :binary.copy(<<0, 1>>, 160_001)] do
      File.write!(Keyword.fetch!(options, :fixture_path), pcm)
      assert Probe.run(options, hooks()).terminal == :invalid_input
    end

    refute_received :credential_resolved
    refute_received :connector_called
  end

  test "bounds cover turns, retained text and callback mailbox forwarding", context do
    turn_limit = Enum.map(0..16, &turn(&1 + 1, "small", "Update", &1))

    text_limit = [
      turn(1, String.duplicate("a", 40_000)),
      turn(2, String.duplicate("b", 40_000), "Update", 1)
    ]

    event_limit = Enum.map(1..256, &turn(&1, "small"))

    for events <- [turn_limit, text_limit, event_limit] do
      result = Probe.run(context.options, hooks(after_finish: events ++ [:normal_close]))
      assert result.terminal == :limit
      refute result.passed?
    end

    callback = Probe.callback_state(self(), make_ref())

    final =
      Enum.reduce(1..1_000, callback, fn _, state ->
        {:ok, next} = Probe.handle_frame({:text, JSON.encode!(turn(1, "bounded"))}, state)
        next
      end)

    assert final.events == 257
    assert length(drain(callback.reference)) == 257
  end

  test "credential/connector exceptions and provider errors never expose private inputs",
       context do
    secret = "synthetic-private-marker"

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        result = Probe.run(context.options, Map.put(hooks(), :credential, fn -> raise secret end))
        assert result.terminal == :unavailable
        refute inspect(result) =~ secret

        result =
          Probe.run(context.options, Map.put(hooks(), :connect, fn _, _ -> {:error, secret} end))

        assert result.terminal == :unavailable
        refute inspect(result) =~ secret
      end)

    refute log =~ secret
    refute log =~ @tail
  end

  defp hooks(options \\ []) do
    %{
      now: fn -> Process.get(:probe_clock) end,
      credential: fn ->
        send(self(), :credential_resolved)
        "synthetic-key"
      end,
      connect: fn connection, callback ->
        assert Keyword.fetch!(connection, :connection).headers == [
                 {"Authorization", "Token synthetic-key"}
               ]

        send(self(), :connector_called)
        Process.put(:probe_callback, callback)
        emit(Keyword.get(options, :initial, [connected()]))
        {:ok, self()}
      end,
      send: fn _, frame ->
        Process.put(:probe_frames, [frame | Process.get(:probe_frames)])

        if match?({:binary, _}, frame) and not Process.get(:probe_sent_before, false) do
          Process.put(:probe_sent_before, true)
          emit(Keyword.get(options, :before_finish, []))
        end

        if match?({:text, _}, frame),
          do: emit(Keyword.get(options, :after_finish, [turn(1, @tail), :normal_close]))

        if elem(frame, 0) == Keyword.get(options, :fail_send), do: {:error, :synthetic}, else: :ok
      end,
      stop: fn _ ->
        Process.delete(:probe_sent_before)
        send(self(), :cleanup_called)
        :ok
      end
    }
  end

  defp emit(events), do: Enum.each(events, &emit_one/1)
  defp emit_one({:clock, time}), do: Process.put(:probe_clock, time)
  defp emit_one(:end_only), do: emit_one(turn(1, @tail, "EndOfTurn"))
  defp emit_one(:normal_close), do: emit_one({:close, :normal_or_no_status})

  defp emit_one({:close, code}) do
    {:ok, callback} = Probe.handle_peer_close(code, Process.get(:probe_callback))
    Process.put(:probe_callback, callback)
  end

  defp emit_one(:disconnect) do
    {:ok, callback} = Probe.handle_disconnect(:connection_lost, Process.get(:probe_callback))
    Process.put(:probe_callback, callback)
  end

  defp emit_one(message) do
    payload = if is_binary(message), do: message, else: JSON.encode!(message)
    {:ok, callback} = Probe.handle_frame({:text, payload}, Process.get(:probe_callback))
    Process.put(:probe_callback, callback)
  end

  defp connected, do: %{"type" => "Connected", "request_id" => "synthetic", "sequence_id" => 0}

  defp turn(sequence, text, event \\ "Update", index \\ 0) do
    %{
      "type" => "TurnInfo",
      "request_id" => "synthetic",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => index,
      "audio_window_start" => 0.0,
      "audio_window_end" => 0.1,
      "transcript" => text,
      "words" => [],
      "end_of_turn_confidence" => 0.9,
      "trigger" => "model"
    }
  end

  defp drain(reference) do
    receive do
      {:flux_close_probe, ^reference, _, event} -> [event | drain(reference)]
    after
      0 -> []
    end
  end
end
