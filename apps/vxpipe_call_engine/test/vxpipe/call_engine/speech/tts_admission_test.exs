defmodule Vxpipe.CallEngine.Speech.TTSAdmissionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Request, Session}
  alias Vxpipe.CallEngine.{SpeechSessionOwner, SpeechTTSAdmissionProbe}

  test "engine admission returns a request while provider acceptance is held" do
    {owner, allocation, tasks} = start_session(:accept)
    provider = Session.provider(allocation)
    job = speak(tasks, owner, allocation)
    assert_receive {:tts_acceptance_held, reference}, 500

    try do
      assert_receive {:admitted, {:ok, %Request{} = request}}, 500
      assert request.ref == reference
      assert request.session == allocation
      assert request.consumer == owner
      assert request.input_characters == 1
      assert request.usage_identity.provider == :morse_code
      assert request.format.sample_rate == 8_000
      refute_received {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :input_submitted}}}
      assert {:error, :busy} = run(owner, fn -> Session.speak(allocation, "T") end)

      send(provider, :release_acceptance)
      assert event(owner, allocation, :input_submitted).request_ref == reference
      assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, audio}}, 500
      assert audio.request_ref == reference
      assert :ok = run(owner, fn -> Session.validate_audio(allocation, audio) end)
      Task.await(job, 1_000)
    after
      send(provider, :release_acceptance)
      run(owner, fn -> Session.close(allocation) end)
    end
  end

  test "clean provider rejection is one failed request and leaves the allocation usable" do
    {owner, allocation, tasks} = start_session(:reject)
    provider = Session.provider(allocation)
    job = speak(tasks, owner, allocation)
    assert_receive {:tts_acceptance_held, reference}, 500

    try do
      assert_receive {:admitted, {:ok, %Request{} = request}}, 500
      assert request.ref == reference
      send(provider, :release_acceptance)
      failed = event(owner, allocation, :failed)
      assert failed.request_ref == reference
      assert failed.reason == :unsupported_character
      refute_received {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :input_submitted}}}

      assert {:ok, replacement} = run(owner, fn -> Session.speak(allocation, "T") end)
      assert event(owner, allocation, :input_submitted).request_ref == replacement.ref
      assert_receive {:speech_owner, ^owner, {:vxpipe_speech_audio, audio}}, 500
      assert audio.request_ref == replacement.ref
      assert :ok = run(owner, fn -> Session.validate_audio(allocation, audio) end)
      refute_received {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :failed}}}
      Task.await(job, 1_000)
    after
      send(provider, :release_acceptance)
      run(owner, fn -> Session.close(allocation) end)
    end
  end

  defp start_session(mode) do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        owner: owner,
        provider: SpeechTTSAdmissionProbe,
        call_timeout: 2_000,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), admission_mode: mode, emit_interval_ms: 0]
      )

    event(owner, allocation, :ready, 5_000)
    {owner, allocation, tasks}
  end

  defp speak(tasks, owner, allocation) do
    observer = self()

    Task.Supervisor.async_nolink(tasks, fn ->
      send(observer, {:admitted, run(owner, fn -> Session.speak(allocation, "E") end)})
    end)
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
