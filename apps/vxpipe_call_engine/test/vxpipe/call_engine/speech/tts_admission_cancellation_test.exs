defmodule Vxpipe.CallEngine.Speech.TTSAdmissionCancellationTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, Event, Input, Session}
  alias Vxpipe.CallEngine.{SpeechSessionOwner, SpeechTTSAdmissionProbe}

  for pending? <- [false, true] do
    @tag pending_input?: pending?
    test "held-credit cancellation permits replacement with pending speak result #{pending?}", %{
      pending_input?: pending?
    } do
      {owner, allocation, tasks} = start_session()
      provider = Session.provider(allocation)
      input = GenServer.whereis(Input.address(allocation))
      channel = GenServer.whereis(Channel.address(allocation))
      assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
      reference = request.ref
      assert_receive {:tts_acceptance_held, ^reference}, 500
      :erlang.suspend_process(input)

      try do
        send(provider, :release_acceptance)
        event(owner, allocation, :input_submitted)
        assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, audio}}, 500
        assert audio.request_ref == reference
        assert :ok = run(owner, fn -> Session.validate_audio(allocation, audio) end)

        if not pending?, do: finish_speak(input, channel, true)
        {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)
        observer = self()

        :ok =
          :sys.install(
            channel,
            {fn state, event, _extra ->
               case event do
                 {:in, {:"$gen_call", _from, {:command, _, _, {:cancel, _, _, _}}}} ->
                   send(observer, :cancel_entered)

                 _ ->
                   :ok
               end

               state
             end, nil}
          )

        job =
          Task.Supervisor.async_nolink(tasks, fn ->
            run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
          end)

        assert_receive :cancel_entered, 500
        _ = :sys.get_state(channel)
        if pending?, do: finish_speak(input, channel, false)
        result = Task.await(job, 1_000)
        assert %{input: nil} = :sys.get_state(channel)

        case result do
          {:ok, playback} ->
            assert playback.request_played_ms == 0
            event(owner, allocation, :cancelled)
            assert {:ok, replacement} = run(owner, fn -> Session.speak(allocation, "T") end)
            assert event(owner, allocation, :input_submitted).request_ref == replacement.ref
            assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, fresh}}, 500
            assert fresh.request_ref == replacement.ref
            assert :ok = run(owner, fn -> Session.validate_audio(allocation, fresh) end)

          error ->
            # Retain the actual consequence as failure evidence. The original
            # speak is now finished; only the uncompleted fence remains pending.
            monitors =
              for pid <- [
                    provider,
                    channel,
                    Session.tree(allocation)
                  ],
                  do: {pid, Process.monitor(pid)}

            assert_receive {:speech_owner, ^owner,
                            {:vxpipe_speech_closed, ^allocation, :command_timeout}},
                           1_000

            for {pid, monitor} <- monitors do
              assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 500
            end

            replacement = run(owner, fn -> Session.speak(allocation, "T") end)
            assert replacement == {:error, :closed}

            flunk(
              "cancel returned #{inspect(error)} after fencing; speak then finished, but the fence expired, descendants terminated and replacement returned #{inspect(replacement)}"
            )
        end
      after
        resume(input)
        run(owner, fn -> Session.close(allocation) end)
      end
    end
  end

  test "clean rejection after fencing settles when cancel arrives later" do
    {owner, allocation, _tasks} = start_session(admission_mode: :reject)
    provider = Session.provider(allocation)

    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:tts_acceptance_held, reference}, 500
    assert reference == request.ref
    assert {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)

    send(provider, :release_acceptance)
    failed = event(owner, allocation, :failed)
    assert failed.request_ref == request.ref
    assert failed.reason == :unsupported_character

    assert {:ok, playback} = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
    assert playback.request_ref == request.ref
    assert playback.request_played_ms == 0
    assert {:ok, ^playback} = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)

    assert {:ok, replacement} = run(owner, fn -> Session.speak(allocation, "T") end)
    assert event(owner, allocation, :input_submitted).request_ref == replacement.ref
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, fresh}}, 500
    assert fresh.request_ref == replacement.ref
  end

  defp finish_speak(input, channel, expect_idle?) do
    :erlang.resume_process(input)
    _ = :sys.get_state(input)
    state = :sys.get_state(channel)
    if expect_idle?, do: assert(%{input: nil} = state)
  end

  defp resume(pid) do
    :erlang.resume_process(pid)
  rescue
    ArgumentError -> :ok
  end

  defp start_session(private_overrides \\ []) do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        owner: owner,
        provider: SpeechTTSAdmissionProbe,
        call_timeout: 500,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: Keyword.merge([observer: self(), emit_interval_ms: 0], private_overrides)
      )

    event(owner, allocation, :ready, 5_000)
    {owner, allocation, tasks}
  end

  defp event(owner, allocation, kind, timeout \\ 500) do
    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech, %Event{session: ^allocation} = event}},
                   timeout

    assert event.kind == kind
    assert :ok = run(owner, fn -> Session.ack(allocation, event) end)
    event
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
