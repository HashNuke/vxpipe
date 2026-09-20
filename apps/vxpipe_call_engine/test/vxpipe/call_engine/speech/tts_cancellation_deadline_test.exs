defmodule Vxpipe.CallEngine.Speech.TTSCancellationDeadlineTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionOwner

  test "cancelled terminal processed after its original deadline is not published" do
    {owner, allocation, request, tasks} = held_request()
    channel = GenServer.whereis(Channel.address(allocation))
    observer = self()
    descendants = monitor_allocation(allocation)
    {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)

    :ok =
      :sys.install(
        channel,
        {fn state, event, _extra ->
           case event do
             {:in,
              {:"$gen_call", _from, {:emit, %Event{kind: :cancelled, request_ref: ^request}}}} ->
               send(observer, :terminal_waiting)

               receive do
                 :release_terminal -> :done
               end

             _ ->
               state
           end
         end, nil}
      )

    job = invoke(tasks, owner, fn -> Session.cancel(allocation, ticket, 0) end)
    assert_receive :terminal_waiting, 500

    try do
      await_deadline(ticket.deadline)
      send(channel, :release_terminal)
      assert_terminated(descendants)
    after
      resume(channel)
      Task.await(job, 5_000)
    end

    assert :ok = run(owner, fn -> :ok end)
    refute_received {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :cancelled}}}
  end

  test "a repeated pending fence cannot return its expired ticket ahead of the watchdog" do
    {owner, allocation, request, tasks} = held_request()
    channel = GenServer.whereis(Channel.address(allocation))
    observer = self()
    {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)
    descendants = monitor_allocation(allocation)

    :ok =
      :sys.install(
        channel,
        {fn state, event, _extra ->
           case event do
             {:in, {:"$gen_call", _from, {:command, _, _, {:fence_output, _, ^request}}}} ->
               send(observer, :repeat_waiting)

               receive do
                 :release_repeat -> :done
               end

             _ ->
               state
           end
         end, nil}
      )

    # Give the repeat a later API deadline while retaining the fence's original deadline.
    tick = make_ref()
    Process.send_after(self(), tick, 100)
    assert_receive ^tick, 500
    job = invoke(tasks, owner, fn -> Session.fence_output(allocation, request) end)
    assert_receive :repeat_waiting, 500
    await_deadline(ticket.deadline)
    send(channel, :release_repeat)
    Task.await(job, 5_000)
    assert_receive {:operation_result, {:error, :command_timeout}}, 500
    assert_terminated(descendants)
  end

  test "interruption retains actual playback from an accepted but uncredited chunk" do
    {owner, allocation, request, _tasks} = held_request()
    {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)

    # The caller reports 10 ms played from a 20 ms chunk. No credit ACK reached
    # Channel; this tests report accounting, not physical playback by a real sink.
    assert {:error, :invalid_playback} =
             run(owner, fn -> Session.cancel(allocation, ticket, 21) end)

    assert {:ok, playback} = run(owner, fn -> Session.cancel(allocation, ticket, 10) end)
    assert playback.request_played_ms == 10
    assert playback.session_played_ms == 10
    event(owner, allocation, :cancelled)
    assert {:ok, ^playback} = run(owner, fn -> Session.cancel(allocation, ticket, 10) end)
    assert {:ok, _replacement} = run(owner, fn -> Session.speak(allocation, "T") end)
    assert :ok = run(owner, fn -> Session.close(allocation) end)
  end

  defp held_request do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: MorseSession,
        owner: owner,
        call_timeout: 500,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [emit_interval_ms: 0]
      )

    event(owner, allocation, :ready, 5_000)
    assert {:ok, %{ref: request}} = run(owner, fn -> Session.speak(allocation, "E") end)
    event(owner, allocation, :input_submitted)
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, %{session: ^allocation}}}, 500
    {owner, allocation, request, tasks}
  end

  defp event(owner, allocation, kind, timeout \\ 500) do
    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech, %Event{session: ^allocation} = event}},
                   timeout

    assert event.kind == kind
    assert :ok = run(owner, fn -> Session.ack(allocation, event) end)
    event
  end

  defp monitor_allocation(allocation) do
    for pid <- [
          Session.provider(allocation),
          GenServer.whereis(Channel.address(allocation)),
          Session.tree(allocation)
        ],
        do: {pid, Process.monitor(pid)}
  end

  defp assert_terminated(descendants) do
    for {pid, monitor} <- descendants do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 500
    end
  end

  defp await_deadline(deadline) do
    tick = make_ref()
    Process.send_after(self(), tick, max(deadline - System.monotonic_time(:millisecond), 0) + 1)
    assert_receive ^tick, 1_000
  end

  defp resume(pid) do
    :erlang.resume_process(pid)
  rescue
    ArgumentError -> :ok
  end

  defp invoke(tasks, owner, operation) do
    observer = self()

    Task.Supervisor.async_nolink(tasks, fn ->
      send(observer, {:operation_result, run(owner, operation)})
    end)
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
