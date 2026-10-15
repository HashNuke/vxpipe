defmodule Vxpipe.Providers.MorseCodeApi.TTSRequestTest do
  use ExUnit.Case, async: true
  @moduletag :integration
  @moduletag :capture_log

  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, TTS, TTSRequest}

  test "streams complete PCM samples over the ElevenLabs WebSocket protocol" do
    owner = self()

    task =
      request(fn audio ->
        send(owner, {:pcm, audio})
        :ok
      end)

    peer = assert_input()
    send(peer, {:send, [audio(<<1>>), audio(<<0, 2, 0>>), final()]})
    assert :ok = Task.await(task)
    assert_receive {:pcm, <<1, 0, 2, 0>>}
    assert_receive {:speech_wire_closed, ^peer}
  end

  test "completion waits for consumer credit and cancellation closes the owned connection" do
    owner = self()

    task =
      request(fn pcm ->
        send(owner, {:waiting_for_credit, self(), pcm})

        receive do
          :credit -> :ok
        end
      end)

    peer = assert_input()
    send(peer, {:send, [audio(<<1, 0>>), final()]})
    assert_receive {:waiting_for_credit, worker, <<1, 0>>}
    task_ref = task.ref
    refute_receive {^task_ref, :ok}
    monitor = Process.monitor(worker)
    Task.shutdown(task, :brutal_kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert_receive {:speech_wire_closed, ^peer}
  end

  test "a partial audio response is not successful without isFinal" do
    task = request(fn _ -> :ok end)
    peer = assert_input()
    send(peer, {:send, [audio(<<1, 0>>)]})
    send(peer, :close)
    assert {:error, :provider_unavailable} = Task.await(task)
  end

  for frames <- [
        [{:text, ~s({"audio":"not base64!"})}],
        [{:text, ~s({"error":"invalid_text"})}],
        [{:text, ~s({"audio":"AQ=="})}, {:text, ~s({"isFinal":true})}],
        [{:text, ~s({"isFinal":true})}]
      ] do
    test "rejects malformed or incomplete audio #{inspect(frames)}" do
      task = request(fn _ -> :ok end)
      peer = assert_input()
      send(peer, {:send, unquote(Macro.escape(frames))})
      assert {:error, :provider_unavailable} = Task.await(task)
      assert_receive {:speech_wire_closed, ^peer}
    end
  end

  test "consumer rejection cannot produce a successful completion" do
    task = request(fn _ -> {:error, :closed} end)
    peer = assert_input()
    send(peer, {:send, [audio(<<1, 0>>), final()]})
    assert {:error, :provider_unavailable} = Task.await(task)
  end

  test "an upgrade failure is not retried or exposed" do
    task = request(fn _ -> flunk("unexpected audio") end, response: :reject)
    assert {:error, :provider_unavailable} = Task.await(task)
    assert_receive {:speech_wire_authorization, []}
    refute_receive {:speech_wire_authorization, _}
  end

  defp request(consume, options \\ []) do
    server = start_supervised!({TestSpeechWireServer, Keyword.put(options, :owner, self())})

    origin =
      server
      |> TestSpeechWireServer.endpoint()
      |> URI.new!()
      |> Map.put(:path, nil)
      |> Map.put(:scheme, "http")
      |> URI.to_string()

    assert {:ok, endpoint} = Endpoint.new(origin, allow_http?: true)
    assert {:ok, config} = TTS.new([api_key: "synthetic"], endpoint)
    supervisor = start_supervised!(Task.Supervisor)
    Task.Supervisor.async_nolink(supervisor, fn -> TTSRequest.run(config, "SOS", consume) end)
  end

  defp assert_input do
    assert_receive {:speech_wire_connected, peer}

    for expected <- [%{"text" => " "}, %{"text" => "SOS"}, %{"text" => ""}] do
      assert_receive {:speech_wire_frame, ^peer, :text, payload}
      assert JSON.decode!(payload) == expected
    end

    peer
  end

  defp audio(bytes), do: {:text, JSON.encode!(%{audio: Base.encode64(bytes), isFinal: false})}
  defp final, do: {:text, JSON.encode!(%{audio: nil, isFinal: true})}
end
