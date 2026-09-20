defmodule Vxpipe.CallEngine.Speech.TTSCancellationTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Session}

  test "fencing held credit cancels once and permits clean different-text replacement" do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: MorseSession,
        call_timeout: 500,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [emit_interval_ms: 0]
      )

    event(allocation, :ready, 5_000)
    provider = Session.provider(allocation)
    channel = GenServer.whereis(Channel.address(allocation))
    assert {:ok, %{ref: first}} = Session.speak(allocation, "E")
    assert event(allocation, :input_submitted).request_ref == first
    assert_receive {:vxpipe_speech_audio, %{session: ^allocation, request_ref: ^first} = old}, 500
    assert :ok = Session.validate_audio(allocation, old)

    assert {:ok, ticket} = Session.fence_output(allocation, first)
    assert {:ok, ^ticket} = Session.fence_output(allocation, first)
    assert {:error, :stale_audio} = Session.validate_audio(allocation, old)
    assert {:error, :stale_audio} = Session.ack_audio(allocation, old)

    # The controlled sink accepted/played no bytes; interruption is already complete.
    assert {:ok, playback} = Session.cancel(allocation, ticket, 0)
    assert playback.request_ref == first
    assert playback.request_played_ms == 0
    assert playback.session_played_ms == 0
    assert event(allocation, :cancelled).request_ref == first
    assert {:ok, ^playback} = Session.cancel(allocation, ticket, 0)

    assert {:ok, %{ref: replacement}} = Session.speak(allocation, "T")
    assert replacement != first
    assert event(allocation, :input_submitted).request_ref == replacement

    send(provider, {:vxpipe_speech_credit, channel, first, old.ref, :ok})
    send(provider, {:emit, first})
    send(channel, {:credit_expired, old.ref})
    _ = :sys.get_state(provider)
    assert {:error, :stale_audio} = Session.ack_audio(allocation, old)

    tick = make_ref()

    Process.send_after(
      self(),
      tick,
      max(ticket.deadline - System.monotonic_time(:millisecond), 0) + 1
    )

    assert_receive ^tick, 1_000
    assert {:ok, ^playback} = Session.cancel(allocation, ticket, 0)
    assert {:error, :conflicting_playback} = Session.cancel(allocation, ticket, 1)

    actual = drain(allocation, replacement, [])
    assert actual == expected_t()
    refute_received {:vxpipe_speech, %Event{session: ^allocation, kind: :cancelled}}
    assert :ok = Session.close(allocation)
  end

  test "abandoning a fence expires its original budget and retires its descendants" do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree), provider: MorseSession, call_timeout: 100)

    event(allocation, :ready, 5_000)
    assert {:ok, %{ref: request}} = Session.speak(allocation, "E")
    event(allocation, :input_submitted)
    assert_receive {:vxpipe_speech_audio, %{session: ^allocation}}, 500

    monitors =
      for pid <- [
            Session.provider(allocation),
            GenServer.whereis(Channel.address(allocation)),
            Session.tree(allocation)
          ],
          do: {pid, Process.monitor(pid)}

    assert {:ok, ticket} = Session.fence_output(allocation, request)
    assert {:ok, ^ticket} = Session.fence_output(allocation, request)
    assert_receive {:vxpipe_speech_closed, ^allocation, _reason}, 500

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 500
    end

    assert {:error, :closed} = Session.speak(allocation, "T")
  end

  test "repeating a settled fence preserves the usable allocation" do
    {allocation, request, _audio} = held_request()
    assert {:ok, ticket} = Session.fence_output(allocation, request)
    assert {:ok, _playback} = Session.cancel(allocation, ticket, 0)
    event(allocation, :cancelled)

    repeated = Session.fence_output(allocation, request)
    replacement = Session.speak(allocation, "T")

    assert repeated == {:ok, ticket},
           "repeated fence returned #{inspect(repeated)}; replacement returned #{inspect(replacement)}"

    assert {:ok, _replacement} = replacement
    assert :ok = Session.close(allocation)
  end

  test "stale credit and generation messages cannot affect replacement output" do
    {allocation, request, old} = held_request()
    channel = GenServer.whereis(Channel.address(allocation))
    provider = Session.provider(allocation)
    observer = self()
    assert {:ok, ticket} = Session.fence_output(allocation, request)

    assert {:ok, _playback} = Session.cancel(allocation, ticket, 0)
    event(allocation, :cancelled)

    :ok =
      :sys.install(
        provider,
        {fn state, event, _extra ->
           case event do
             {:out, :ok, _from, %{request: reference}} when reference != request ->
               send(observer, :replacement_accepted)

               receive do
                 :release_replacement -> :done
               end

             _ ->
               state
           end
         end, nil}
      )

    try do
      assert {:ok, %{ref: replacement}} = Session.speak(allocation, "T")
      assert_receive :replacement_accepted, 500
      assert event(allocation, :input_submitted).request_ref == replacement
      send(provider, {:vxpipe_speech_credit, channel, request, old.ref, :ok})
      send(provider, {:emit, request})
      send(channel, {:credit_expired, old.ref})
      _ = :sys.get_state(channel)
      refute_received {:vxpipe_speech_audio, %{session: ^allocation, request_ref: ^request}}
    after
      send(provider, :release_replacement)
      Session.close(allocation)
    end
  end

  test "a foreign caller timing out on an old ticket cannot retire the replacement" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    {allocation, request, _audio} = held_request(call_timeout: 100)
    {:ok, ticket} = Session.fence_output(allocation, request)
    {:ok, playback} = Session.cancel(allocation, ticket, 0)
    event(allocation, :cancelled)
    {:ok, %{ref: replacement}} = Session.speak(allocation, "T")
    event(allocation, :input_submitted)
    assert_receive {:vxpipe_speech_audio, %{request_ref: ^replacement} = audio}, 500
    channel = GenServer.whereis(Channel.address(allocation))
    :ok = :sys.suspend(channel)
    job = Task.Supervisor.async_nolink(tasks, fn -> Session.cancel(allocation, ticket, 0) end)

    try do
      assert {:error, :command_timeout} = Task.await(job, 1_000)
    after
      :ok = :sys.resume(channel)
    end

    _ = :sys.get_state(channel)
    assert :ok = Session.validate_audio(allocation, audio)
    assert {:ok, ^playback} = Session.cancel(allocation, ticket, 0)
    assert {:ok, ^ticket} = Session.fence_output(allocation, request)

    foreign = Task.Supervisor.async_nolink(tasks, fn -> Session.cancel(allocation, ticket, 0) end)
    assert {:error, :not_owner} = Task.await(foreign, 1_000)
    assert :ok = Session.close(allocation)
  end

  defp held_request(overrides \\ []) do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(
        CapabilityTree.scope(tree),
        Keyword.merge(
          [
            provider: MorseSession,
            options: [sample_rate: 8_000, unit_duration_ms: 20],
            private: [emit_interval_ms: 0]
          ],
          overrides
        )
      )

    event(allocation, :ready, 5_000)
    assert {:ok, %{ref: request}} = Session.speak(allocation, "E")
    event(allocation, :input_submitted)
    assert_receive {:vxpipe_speech_audio, %{session: ^allocation} = audio}, 500
    {allocation, request, audio}
  end

  defp event(allocation, kind, timeout \\ 500) do
    assert_receive {:vxpipe_speech, %Event{session: ^allocation} = event}, timeout
    assert event.kind == kind
    assert :ok = Session.ack(allocation, event)
    event
  end

  defp drain(allocation, reference, chunks) do
    receive do
      {:vxpipe_speech_audio, %{session: ^allocation, request_ref: ^reference} = audio} ->
        assert :ok = Session.validate_audio(allocation, audio)
        assert :ok = Session.ack_audio(allocation, audio)
        drain(allocation, reference, [audio.payload | chunks])

      {:vxpipe_speech, %Event{session: ^allocation, kind: :completed} = completed} ->
        assert completed.request_ref == reference
        assert :ok = Session.ack(allocation, completed)
        chunks |> Enum.reverse() |> IO.iodata_to_binary()
    after
      1_000 -> flunk("replacement did not complete")
    end
  end

  defp expected_t do
    dash =
      for index <- 0..479, into: <<>> do
        sample = round(:math.sin(2.0 * :math.pi() * 700 / 8_000 * index) * 4_096)
        <<sample::signed-little-16>>
      end

    dash <> :binary.copy(<<0, 0>>, 2_240)
  end
end
