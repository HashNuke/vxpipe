defmodule Vxpipe.CallEngine.Speech.TTSCompletionOrderTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.{SpeechSessionOwner, SpeechTTSCompletionProbe}

  for result <- [:ok, {:error, :session_failed}] do
    test "playback settlement waits for pending callback result #{inspect(result)}" do
      {owner, allocation, provider, tasks} = start_session()
      assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
      event(owner, allocation, :input_submitted)
      assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, audio}}, 500
      assert :ok = run(owner, fn -> Session.ack_audio(allocation, audio) end)
      assert_receive {:tts_completion_callback_held, reference}, 500
      assert reference == request.ref
      completed = event(owner, allocation, :completed)
      assert completed.request_ref == request.ref

      observer = self()

      settlement =
        Task.Supervisor.async_nolink(tasks, fn ->
          result = run(owner, fn -> Session.settle_output(allocation, request, 0) end)
          send(observer, {:settled, result})
        end)

      refute_receive {:settled, _premature_result}, 100
      send(provider, {:release_callback, unquote(Macro.escape(result))})
      assert_receive {:settled, unquote(Macro.escape(result))}, 500
      Task.await(settlement)

      case unquote(Macro.escape(result)) do
        :ok ->
          assert {:ok, _replacement} = run(owner, fn -> Session.speak(allocation, "T") end)

        {:error, :session_failed} ->
          assert_receive {:speech_owner, ^owner,
                          {:vxpipe_speech_closed, ^allocation, :session_failed}},
                         500
      end
    end
  end

  test "the original input deadline closes a pending playback settlement" do
    {owner, allocation, provider, tasks} = start_session()
    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    event(owner, allocation, :input_submitted)
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, audio}}, 500
    assert :ok = run(owner, fn -> Session.ack_audio(allocation, audio) end)
    assert_receive {:tts_completion_callback_held, _reference}, 500
    event(owner, allocation, :completed)
    observer = self()

    settlement =
      Task.Supervisor.async_nolink(tasks, fn ->
        result = run(owner, fn -> Session.settle_output(allocation, request, 0) end)
        send(observer, {:settled, result})
      end)

    refute_receive {:settled, _premature_result}, 100
    channel = GenServer.whereis(Channel.address(allocation))
    command = :sys.get_state(channel).input.command
    monitor = Process.monitor(provider)
    send(channel, {:input_expired, command.ref})

    assert_receive {:settled, {:error, :session_failed}}, 500
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 500
    Task.await(settlement)
  end

  defp start_session do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        owner: owner,
        provider: SpeechTTSCompletionProbe,
        options: [sample_rate: 8_000],
        private: [observer: self()]
      )

    event(owner, allocation, :ready)
    {owner, allocation, Session.provider(allocation), tasks}
  end

  defp event(owner, allocation, kind) do
    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech, %Event{session: ^allocation, kind: ^kind} = event}},
                   500

    assert :ok = run(owner, fn -> Session.ack(allocation, event) end)
    event
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
