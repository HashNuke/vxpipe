defmodule Vxpipe.CallEngine.Integration.FluxCloseProbeLoopbackTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{TestFluxCloseProbe, TestSpeechWireServer}

  @moduletag :integration
  @moduletag :tmp_dir

  test "test-only runner observes actual Socket PCM/control order and final peer callback", %{
    tmp_dir: directory
  } do
    path = Path.join(directory, "synthetic.pcm")
    pcm = :binary.copy(<<0, 1>>, 3_000)
    File.write!(path, pcm)
    server = start_supervised!({TestSpeechWireServer, owner: self()})
    endpoint = TestSpeechWireServer.endpoint(server)
    sockets = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    tasks = start_supervised!({Task.Supervisor, []})
    owner = self()

    probe =
      Task.Supervisor.async_nolink(tasks, fn ->
        TestFluxCloseProbe.run(
          [
            enabled: true,
            fixture_path: path,
            expected_tail: "synthetic final tail.",
            timeout_ms: 5_000
          ],
          %{
            credential: fn -> "synthetic-key" end,
            connect: fn options, callback ->
              # The only endpoint override is in this local test's injected connector.
              connection = Keyword.fetch!(options, :connection)
              options = Keyword.put(options, :connection, %{connection | url: endpoint})

              result =
                TestFluxCloseProbe.start_socket(options, callback, fn specification ->
                  DynamicSupervisor.start_child(sockets, specification)
                end)

              {:ok, socket} = result
              send(owner, {:probe_socket, socket})
              result
            end,
            stop: fn socket -> DynamicSupervisor.terminate_child(sockets, socket) end
          }
        )
      end)

    assert_receive {:probe_socket, socket}
    assert_receive {:speech_wire_connected, peer}, 1_000
    assert_receive {:speech_wire_authorization, ["Token synthetic-key"]}

    connected =
      JSON.encode!(%{"type" => "Connected", "request_id" => "synthetic", "sequence_id" => 0})

    send(peer, {:send, [{:text, connected}]})

    for expected <- [
          binary_part(pcm, 0, 2_560),
          binary_part(pcm, 2_560, 2_560),
          binary_part(pcm, 5_120, 880)
        ] do
      assert_receive {:speech_wire_frame, ^peer, :binary, ^expected}, 1_000
    end

    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"CloseStream"})}, 1_000
    refute_received {:speech_wire_frame, ^peer, :close, _}

    private_tail = "synthetic final tail."

    tail =
      JSON.encode!(%{
        "type" => "TurnInfo",
        "request_id" => "synthetic",
        "sequence_id" => 1,
        "event" => "Update",
        "turn_index" => 0,
        "audio_window_start" => 0.0,
        "audio_window_end" => 0.1,
        "transcript" => private_tail,
        "words" => [],
        "end_of_turn_confidence" => 0.9
      })

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(peer, {:send, [{:text, tail}]})
        # Ordered messages from this owner queue the tail before the peer close.
        send(peer, :close)
        result = Task.await(probe, 6_000)
        assert result.passed?
        assert result.terminal == :normal_or_no_status
        refute inspect(result) =~ private_tail
      end)

    refute log =~ private_tail
    refute log =~ "synthetic-key"
    # Socket status redaction itself is covered by the existing privacy group.
    refute_received {:flux_close_probe, _, ^socket, _}
  end
end
