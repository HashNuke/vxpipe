defmodule Vxpipe.CallEngine.Integration.SpeechSocketPeerCloseTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.{Socket, SocketConnection}
  alias Vxpipe.CallEngine.{TestSpeechSocketCloseProbe, TestSpeechUpgradeServer}
  alias Vxpipe.Providers.Deepgram.STTSocket

  @moduletag :integration
  @reason "synthetic-private-peer-close-reason"

  setup do
    peer =
      start_supervised!(
        Supervisor.child_spec({TestSpeechUpgradeServer, owner: self(), frames: []},
          restart: :temporary
        )
      )

    assert_receive {:speech_upgrade_endpoint, endpoint}
    %{peer: peer, endpoint: endpoint}
  end

  test "empty peer close reports only the observed normalized class", context do
    {socket, monitor} = start_socket(context)
    :ok = GenServer.call(context.peer, {:send, [{:text, "tail"}, {:binary, <<0, 1>>}, :close]})

    assert next_event(socket) == {:frame, {:text, "tail"}}
    assert {:awaiting, reference, <<0, 1>>} = next_event(socket)
    _ = :sys.get_state(socket)
    send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})

    assert next_event(socket) == {:peer_close, :normal_or_no_status}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  test "explicit normal status reports the same normalized class without raw reason", context do
    {socket, monitor} = start_socket(context)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        :ok = GenServer.call(context.peer, {:send, [{:close, 1_000, @reason}]})
        assert next_event(socket) == {:peer_close, :normal_or_no_status}
        assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
      end)

    refute log =~ @reason
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  for code <- [1_008, 4_123] do
    test "peer close preserves decoded status #{code} without a raw reason", context do
      {socket, monitor} = start_socket(context)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :ok = GenServer.call(context.peer, {:send, [{:close, unquote(code), @reason}]})
          assert next_event(socket) == {:peer_close, unquote(code)}
          assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
        end)

      refute log =~ @reason
      refute_received {:socket_close_probe, ^socket, _duplicate}
    end
  end

  test "coalesced close waits for preceding frame acknowledgement and hides reason", context do
    {socket, monitor} = start_socket(context)

    :ok =
      GenServer.call(
        context.peer,
        {:send, [{:binary, <<1, 2>>}, {:text, "tail"}, {:close, 1_000, @reason}]}
      )

    assert {:awaiting, reference, <<1, 2>>} = next_event(socket)
    state = :sys.get_state(socket)
    refute inspect(state, limit: :infinity) =~ @reason
    refute inspect(:sys.get_status(socket), limit: :infinity) =~ @reason
    refute_received {:socket_close_probe, ^socket, _premature}

    send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})
    assert next_event(socket) == {:frame, {:text, "tail"}}
    assert next_event(socket) == {:peer_close, :normal_or_no_status}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  test "observed peer code survives close reply failure", context do
    {socket, monitor} = start_socket(context)

    :ok =
      GenServer.call(
        context.peer,
        {:send, [{:binary, <<3, 4>>}, {:close, 1_008, @reason}]}
      )

    assert {:awaiting, reference, <<3, 4>>} = next_event(socket)

    # Keep the already decoded peer close behind the acknowledgement, but close
    # the actual connection so the subsequent reply attempt deterministically fails.
    state =
      :sys.replace_state(socket, fn state ->
        {:ok, conn} = Mint.HTTP.close(state.connection.conn)
        %{state | connection: %{state.connection | conn: conn}}
      end)

    assert {:error, :connection_lost} =
             SocketConnection.send_frame(state.connection, {:close, 1_000, ""})

    send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})
    assert next_event(socket) == {:peer_close, 1_008}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  test "EOF without a close frame remains a generic disconnect", context do
    {socket, monitor} = start_socket(context)
    :ok = GenServer.call(context.peer, {:send, [text: "last observed update"]})
    assert next_event(socket) == {:frame, {:text, "last observed update"}}
    :ok = GenServer.call(context.peer, :disconnect)

    assert next_event(socket) == {:disconnect, :connection_lost}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  test "send failure is not peer-close evidence", context do
    {socket, monitor} = start_socket(context)

    :sys.replace_state(socket, fn state ->
      {:ok, conn} = Mint.HTTP.close(state.connection.conn)
      %{state | connection: %{state.connection | conn: conn}}
    end)

    assert {:error, :connection_lost} = Socket.send_frame(socket, {:text, "unsent"})

    assert next_event(socket) == {:disconnect, :connection_lost}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  test "rejected acknowledgement does not release a queued peer close", context do
    {socket, monitor} = start_socket(context)
    :ok = GenServer.call(context.peer, {:send, [{:binary, <<5, 6>>}, :close]})
    assert {:awaiting, reference, <<5, 6>>} = next_event(socket)
    _ = :sys.get_state(socket)
    send(socket, {:vxpipe_tts_audio_result, self(), reference, {:error, :rejected}})

    assert next_event(socket) == {:disconnect, :connection_lost}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _duplicate}
  end

  test "local close does not fabricate a peer observation", context do
    {socket, monitor} = start_socket(context)
    assert :ok = Socket.close(socket, "local stop")
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:socket_close_probe, ^socket, _event}
  end

  test "existing adapter receives unchanged generic disconnect", context do
    {socket, monitor} = start_socket(context, STTSocket)
    :ok = GenServer.call(context.peer, {:send, [{:close, 1_008, @reason}]})

    assert_receive {:vxpipe_stt_transport, ^socket, {:closed, :connection_lost}}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_received {:vxpipe_stt_transport, ^socket, _duplicate}
  end

  defp start_socket(context, module \\ TestSpeechSocketCloseProbe) do
    options = [
      owner: self(),
      connection: %{url: context.endpoint, headers: []},
      transport_options: [receive_timeout: 1_000]
    ]

    socket =
      start_supervised!(%{
        id: make_ref(),
        start: {module, :start_link, [options]},
        restart: :temporary
      })

    assert_receive {:speech_upgrade_connected, peer}
    assert peer == context.peer
    {socket, Process.monitor(socket)}
  end

  defp next_event(socket) do
    assert_receive {:socket_close_probe, ^socket, event}, 1_000
    event
  end
end
