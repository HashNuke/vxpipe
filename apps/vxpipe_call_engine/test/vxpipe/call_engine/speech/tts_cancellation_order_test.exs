defmodule Vxpipe.CallEngine.Speech.TTSCancellationOrderTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.{SpeechSessionOwner, SpeechTTSCancellationProbe}

  for order <- [:callback_first, :terminal_first] do
    test "replacement waits for callback and terminal in #{order} order" do
      {owner, allocation, request, tasks} = start_request(unquote(order))
      provider = Session.provider(allocation)
      {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)
      observer = self()

      job =
        Task.Supervisor.async_nolink(tasks, fn ->
          result = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
          send(observer, {:operation_result, result})
        end)

      assert_receive {:probe_cancel, ^request, playback}, 500
      assert playback.request_played_ms == 0

      case unquote(order) do
        :callback_first ->
          assert_receive {:operation_result, {:ok, ^playback}}, 500
          assert {:error, :busy} = run(owner, fn -> Session.speak(allocation, "T") end)
          refute_received {:probe_speak, _rejected_request}
          assert :ok = GenServer.call(provider, :emit_cancelled)

        :terminal_first ->
          assert_receive :probe_terminal_accepted, 500
          refute_received {:operation_result, _early_reply}
          send(provider, :release_callback)
          assert_receive {:operation_result, {:ok, ^playback}}, 500
      end

      Task.await(job, 5_000)
      event(owner, allocation, :cancelled)
      assert {:ok, %{ref: replacement}} = run(owner, fn -> Session.speak(allocation, "T") end)
      assert_receive {:probe_speak, ^replacement}, 500
      event(owner, allocation, :input_submitted)
      assert :ok = run(owner, fn -> Session.close(allocation) end)
    end
  end

  test "callback acceptance without terminal isolation expires the original fence" do
    {owner, allocation, request, _tasks} = start_request(:callback_first)

    monitors =
      for pid <- [
            Session.provider(allocation),
            GenServer.whereis(Channel.address(allocation)),
            Session.tree(allocation)
          ],
          do: {pid, Process.monitor(pid)}

    {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)
    assert {:ok, _playback} = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
    assert {:error, :busy} = run(owner, fn -> Session.speak(allocation, "T") end)
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech_closed, ^allocation, _reason}}, 1_000

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 500
    end

    refute_received {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :cancelled}}}
  end

  defp start_request(order) do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        owner: owner,
        provider: SpeechTTSCancellationProbe,
        call_timeout: 500,
        private: [observer: self(), order: order]
      )

    event(owner, allocation, :ready, 5_000)
    assert {:ok, %{ref: request}} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:probe_speak, ^request}, 500
    event(owner, allocation, :input_submitted)
    {owner, allocation, request, tasks}
  end

  defp event(owner, allocation, kind, timeout \\ 500) do
    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech, %Event{session: ^allocation} = event}},
                   timeout

    assert event.kind == kind
    assert :ok = run(owner, fn -> Session.ack(allocation, event) end)
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
