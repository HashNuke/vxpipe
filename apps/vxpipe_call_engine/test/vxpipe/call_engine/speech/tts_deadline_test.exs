defmodule Vxpipe.CallEngine.Speech.TTSDeadlineTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Session}
  alias Vxpipe.CallEngine.SpeechSessionOwner

  test "wrong-direction input rejects without retiring an active TTS allocation" do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree), provider: MorseSession)

    assert_receive {:vxpipe_speech, ready}, 5_000
    assert :ok = Session.ack(allocation, ready)

    assert {:error, :unsupported_operation} = Session.push_audio(allocation, <<0, 0>>)
    assert {:ok, _request} = Session.speak(allocation, "E")
  end

  test "adopted TTS publishes readiness and accepts input through Channel" do
    lease = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: MorseSession,
        consumer: nil,
        lease: lease,
        call_timeout: 500
      )

    assert_receive {:speech_owner, ^lease, {:vxpipe_speech_prepared, ^allocation, _}}, 500
    consumer = self()
    assert :ok = run(lease, fn -> Session.adopt(allocation, consumer) end)
    assert_receive {:vxpipe_speech, ready}, 5_000
    assert :ok = Session.ack(allocation, ready)
    assert {:ok, _request} = Session.speak(allocation, "E")
  end

  test "rejected speak before its original deadline publishes one failure and permits replacement" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    allocation = start_owned(owner)
    provider = Session.provider(allocation)
    observer = self()
    hold_provider_speak(provider, observer)

    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "☃") end)
    assert_receive :speak_waiting, 500
    tick = make_ref()
    Process.send_after(self(), tick, 20)
    assert_receive ^tick, 500
    send(provider, :release_speak)

    assert_receive {:speech_owner, ^owner, {:vxpipe_speech, failed}}, 500
    assert failed.kind == :failed
    assert failed.reason == :unsupported_character
    assert failed.request_ref == request.ref
    assert :ok = run(owner, fn -> Session.ack(allocation, failed) end)
    assert {:ok, _request} = run(owner, fn -> Session.speak(allocation, "E") end)
  end

  test "a provider result held past the original speak deadline retires the allocation" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    allocation = start_owned(owner)
    provider = Session.provider(allocation)
    channel = GenServer.whereis(Channel.address(allocation))
    observer = self()
    hold_provider_speak(provider, observer)

    assert {:ok, _request} = run(owner, fn -> Session.speak(allocation, "☃") end)
    assert_receive :speak_waiting, 500
    %{input: %{command: %{deadline: deadline}}} = :sys.get_state(channel)
    descendants = monitor_allocation(allocation)
    await_deadline(deadline)
    assert_terminated(descendants)

    _ = :sys.get_state(owner)
    refute_received {:speech_owner, ^owner, {:vxpipe_speech, %{kind: :failed}}}
    assert {:error, :closed} = run(owner, fn -> Session.speak(allocation, "E") end)
  end

  defp start_owned(owner) do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: MorseSession,
        owner: owner,
        call_timeout: 500
      )

    assert_receive {:speech_owner, ^owner, {:vxpipe_speech, ready}}, 5_000
    assert :ok = run(owner, fn -> Session.ack(allocation, ready) end)
    allocation
  end

  defp hold_provider_speak(provider, observer) do
    :ok =
      :sys.install(
        provider,
        {fn state, event, _extra ->
           case event do
             {:in, {:"$gen_call", _from, {:speak, _reference, _text}}} ->
               send(observer, :speak_waiting)

               receive do
                 :release_speak -> :done
               end

             _ ->
               state
           end
         end, nil}
      )
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

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
