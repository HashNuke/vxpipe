defmodule Vxpipe.CallEngine.Speech.TTSUsageFactTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Channel, Event, Session, TTSUsage}

  alias Vxpipe.CallEngine.{
    SpeechSessionOwner,
    SpeechTTSAdmissionProbe,
    SpeechTTSUsageProbe
  }

  test "engine admission alone produces no TTS usage snapshot" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechTTSAdmissionProbe,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), admission_mode: :accept, emit_interval_ms: 0]
      )

    event(owner, allocation, :ready)
    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:tts_acceptance_held, reference}, 500
    assert request.ref == reference
    refute_received {:speech_owner, ^owner, {:vxpipe_speech, %Event{usage: %TTSUsage{}}}}

    send(Session.provider(allocation), :release_acceptance)
    submitted = event(owner, allocation, :input_submitted)

    assert %TTSUsage{
             request_ref: ^reference,
             input_characters: 1,
             generated_bytes: 0,
             generation: :submitted
           } = submitted.usage
  end

  test "a definite pre-submission rejection remains zero usage after fenced settlement" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechTTSAdmissionProbe,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), admission_mode: :reject, emit_interval_ms: 0]
      )

    event(owner, allocation, :ready)
    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:tts_acceptance_held, reference}, 500
    assert reference == request.ref
    assert {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)

    send(Session.provider(allocation), :release_acceptance)
    failed = event(owner, allocation, :failed)
    assert failed.request_ref == reference
    assert failed.reason == :unsupported_character
    assert failed.usage == nil
    assert {:ok, playback} = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
    assert playback.request_ref == reference
    refute_received {:speech_owner, ^owner, {:vxpipe_speech_tts_usage, _, _}}
  end

  for failure <- [:allocation, :scope, :owner] do
    @failure failure

    test "submitted and generated snapshots survive #{@failure} failure through exact Channel DOWN" do
      owner = start_supervised!({SpeechSessionOwner, self()}, id: {@failure, :consumer})
      lifetime = start_supervised!({SpeechSessionOwner, self()}, id: {@failure, :lifetime})
      tree = capability_tree()

      {:ok, allocation, :starting} =
        Session.start(CapabilityTree.scope(tree),
          provider: SpeechTTSUsageProbe,
          owner: lifetime,
          consumer: owner,
          usage: true,
          options: [sample_rate: 8_000, unit_duration_ms: 20],
          private: [observer: self()]
        )

      event(owner, allocation, :ready)
      channel = GenServer.whereis(Channel.address(allocation))
      assert is_pid(channel)
      channel_monitor = Process.monitor(channel)

      assert :ok = SpeechSessionOwner.hold(owner)
      assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
      assert_receive {:usage_probe_submitted, request_ref, provider_request_id}, 500
      assert request_ref == request.ref

      allocation_tree = Session.tree(allocation)
      tree_monitor = Process.monitor(allocation_tree)

      case @failure do
        :allocation -> Process.exit(Session.provider(allocation), :kill)
        :scope -> Process.exit(tree, :kill)
        :owner -> Process.exit(lifetime, :kill)
      end

      assert_receive {:DOWN, ^channel_monitor, :process, ^channel, _reason}, 500
      assert_receive {:DOWN, ^tree_monitor, :process, ^allocation_tree, _reason}, 500
      assert :ok = SpeechSessionOwner.release(owner)

      submitted = receive_event(owner, allocation, :input_submitted)

      assert_receive {:speech_owner, ^owner,
                      {:vxpipe_speech_audio, %Audio{session: ^allocation} = audio}},
                     500

      assert provider_request_id == submitted.provider_request_id
      assert audio.request_ref == request.ref
      assert byte_size(audio.payload) == 320

      assert %TTSUsage{
               session: ^allocation,
               request_ref: ^request_ref,
               input_characters: 1,
               usage_identity: %{
                 provider: :morse_code,
                 model: :morse_code,
                 provenance: :locally_measured
               },
               provider_request_id: ^provider_request_id,
               provenance: :locally_measured,
               generated_bytes: 0,
               generation: :submitted
             } = submitted.usage

      assert %TTSUsage{
               session: ^allocation,
               request_ref: ^request_ref,
               provider_request_id: ^provider_request_id,
               generated_bytes: 320,
               generation: :generating
             } = audio.usage

      refute_received {:speech_owner, ^owner, {:vxpipe_speech_tts_usage, _, _}}
    end
  end

  test "completed sink drain keeps generation evidence separate from reported playback" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: Vxpipe.CallEngine.Provider.MorseCodeTTS.Session,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [emit_interval_ms: 0]
      )

    event(owner, allocation, :ready)
    {first, first_submitted, first_audio} = synthesize(owner, allocation, "E")
    first_terminal = event(owner, allocation, :completed)
    assert first_terminal.request_ref == first.ref
    assert first_submitted.generation == :submitted
    assert_monotonic_generation(first_audio)
    assert first_terminal.usage.generation == :completed

    assert {:ok, first_fence} = run(owner, fn -> Session.fence_output(allocation, first) end)

    assert {:ok, first_playback} =
             run(owner, fn -> Session.cancel(allocation, first_fence, 125) end)

    assert first_playback.request_played_ms == 125
    assert first_playback.session_played_ms == 125
    refute_receive {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :cancelled}}}, 50

    {second, _second_submitted, second_audio} = synthesize(owner, allocation, "T")
    second_terminal = event(owner, allocation, :completed)
    assert second_terminal.request_ref == second.ref
    assert_monotonic_generation(second_audio)

    assert {:ok, second_fence} = run(owner, fn -> Session.fence_output(allocation, second) end)

    assert {:ok, second_playback} =
             run(owner, fn -> Session.cancel(allocation, second_fence, 75) end)

    assert second_playback.request_played_ms == 75
    assert second_playback.session_played_ms == 200
    refute_receive {:speech_owner, ^owner, {:vxpipe_speech, %Event{kind: :cancelled}}}, 50
    refute_received {:speech_owner, ^owner, {:vxpipe_speech_tts_usage, _, _}}
  end

  test "final credit gates completion and retains a provider ID first reported at terminal" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechTTSUsageProbe,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), id_at: :terminal]
      )

    event(owner, allocation, :ready)
    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    submitted = receive_event(owner, allocation, :input_submitted)
    assert submitted.provider_request_id == nil
    assert submitted.usage.provider_request_id == nil

    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech_audio, %Audio{session: ^allocation} = audio}},
                   500

    assert audio.usage.provider_request_id == nil

    assert {:error, :stale_audio} =
             run(owner, fn -> Session.validate_audio(allocation, audio) end)

    assert :ok = run(owner, fn -> Session.ack(allocation, submitted) end)
    provider = Session.provider(allocation)
    assert {:error, :output_pending} = GenServer.call(provider, :complete)
    assert :ok = run(owner, fn -> Session.validate_audio(allocation, audio) end)
    assert :ok = run(owner, fn -> Session.ack_audio(allocation, audio) end)
    assert :ok = GenServer.call(provider, :complete)
    terminal = event(owner, allocation, :completed)
    assert is_binary(terminal.provider_request_id)

    assert %TTSUsage{
             request_ref: request_ref,
             generation: :completed,
             generated_bytes: 320,
             provider_request_id: provider_request_id
           } = terminal.usage

    assert request_ref == request.ref
    assert provider_request_id == terminal.provider_request_id
    refute inspect(terminal.usage) =~ provider_request_id
  end

  test "terminal-only provider identity survives scope loss behind a held submission ACK" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechTTSUsageProbe,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), id_at: :terminal, audio?: false]
      )

    event(owner, allocation, :ready)
    channel = GenServer.whereis(Channel.address(allocation))
    assert is_pid(channel)
    channel_monitor = Process.monitor(channel)
    assert :ok = SpeechSessionOwner.hold(owner)

    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:usage_probe_submitted, request_ref, _provider_request_id}, 500
    assert request_ref == request.ref
    assert :ok = GenServer.call(Session.provider(allocation), :complete)

    Process.exit(tree, :kill)
    assert_receive {:DOWN, ^channel_monitor, :process, ^channel, _reason}, 500
    assert :ok = SpeechSessionOwner.release(owner)

    submitted = receive_event(owner, allocation, :input_submitted)
    assert submitted.usage.provider_request_id == nil

    completed = receive_event(owner, allocation, :completed)
    assert is_binary(completed.provider_request_id)
    assert completed.usage.provider_request_id == completed.provider_request_id
    assert completed.usage.generation == :completed
  end

  test "cancelled provider identity survives scope loss behind a held submission ACK" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechTTSUsageProbe,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), id_at: :terminal, audio?: false]
      )

    event(owner, allocation, :ready)
    channel = GenServer.whereis(Channel.address(allocation))
    assert is_pid(channel)
    channel_monitor = Process.monitor(channel)
    assert :ok = SpeechSessionOwner.hold(owner)

    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:usage_probe_submitted, request_ref, _provider_request_id}, 500
    assert request_ref == request.ref
    assert {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)
    assert {:ok, playback} = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
    assert playback.request_ref == request.ref

    Process.exit(tree, :kill)
    assert_receive {:DOWN, ^channel_monitor, :process, ^channel, _reason}, 500
    assert :ok = SpeechSessionOwner.release(owner)

    submitted = receive_event(owner, allocation, :input_submitted)
    assert submitted.usage.provider_request_id == nil

    cancelled = receive_event(owner, allocation, :cancelled)
    assert is_binary(cancelled.provider_request_id)
    assert cancelled.usage.provider_request_id == cancelled.provider_request_id
    assert cancelled.usage.generation == :cancelled
  end

  test "a pre-delivered terminal is promoted after submission ACK without duplication" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechTTSUsageProbe,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [observer: self(), id_at: :terminal, audio?: false]
      )

    event(owner, allocation, :ready)
    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, "E") end)
    assert_receive {:usage_probe_submitted, request_ref, _provider_request_id}, 500
    assert request_ref == request.ref
    assert :ok = GenServer.call(Session.provider(allocation), :complete)

    submitted = receive_event(owner, allocation, :input_submitted)
    completed = receive_event(owner, allocation, :completed)
    assert completed.request_ref == request.ref
    assert {:error, :stale_event} = run(owner, fn -> Session.ack(allocation, completed) end)
    assert :ok = run(owner, fn -> Session.ack(allocation, submitted) end)
    refute_receive {:speech_owner, ^owner, {:vxpipe_speech, ^completed}}, 50
    assert :ok = run(owner, fn -> Session.ack(allocation, completed) end)

    assert {:ok, ticket} = run(owner, fn -> Session.fence_output(allocation, request) end)
    assert {:ok, playback} = run(owner, fn -> Session.cancel(allocation, ticket, 0) end)
    assert playback.request_ref == request.ref
    assert {:ok, replacement} = run(owner, fn -> Session.speak(allocation, "T") end)
    assert replacement.ref != request.ref
    assert receive_event(owner, allocation, :input_submitted).request_ref == replacement.ref
  end

  test "usage delivery cannot queue independently while the consumer advances media" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = capability_tree()

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: Vxpipe.CallEngine.Provider.MorseCodeTTS.Session,
        owner: owner,
        usage: true,
        options: [sample_rate: 8_000, unit_duration_ms: 20],
        private: [emit_interval_ms: 0]
      )

    event(owner, allocation, :ready)
    {request, submitted, audio} = synthesize(owner, allocation, String.duplicate("E", 16))
    terminal = event(owner, allocation, :completed)

    assert submitted.request_ref == request.ref
    assert terminal.usage.request_ref == request.ref
    assert terminal.usage.generated_bytes == 24_000
    assert length(audio) == 75
    assert_monotonic_generation(audio)
    refute_received {:speech_owner, ^owner, {:vxpipe_speech_tts_usage, _, _}}
  end

  defp capability_tree do
    start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))
  end

  defp event(owner, allocation, kind) do
    event = receive_event(owner, allocation, kind)
    assert :ok = run(owner, fn -> Session.ack(allocation, event) end)
    event
  end

  defp receive_event(owner, allocation, kind) do
    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech, %Event{session: ^allocation, kind: ^kind} = event}},
                   5_000

    event
  end

  defp synthesize(owner, allocation, text) do
    assert {:ok, request} = run(owner, fn -> Session.speak(allocation, text) end)
    submitted = event(owner, allocation, :input_submitted)
    assert submitted.request_ref == request.ref
    audio = drain_audio(owner, allocation, request.ref, [])
    {request, submitted.usage, audio}
  end

  defp drain_audio(owner, allocation, request_ref, usage) do
    receive do
      {:speech_owner, ^owner,
       {:vxpipe_speech_audio, %Audio{session: ^allocation, request_ref: ^request_ref} = audio}} ->
        assert %TTSUsage{request_ref: ^request_ref, generation: :generating} = audio.usage
        assert :ok = run(owner, fn -> Session.validate_audio(allocation, audio) end)
        assert :ok = run(owner, fn -> Session.ack_audio(allocation, audio) end)
        drain_audio(owner, allocation, request_ref, [audio.usage | usage])

      {:speech_owner, ^owner,
       {:vxpipe_speech, %Event{session: ^allocation, request_ref: ^request_ref, kind: :completed}} =
           message} ->
        send(self(), {:speech_owner, owner, message})
        Enum.reverse(usage)
    after
      1_000 -> flunk("native TTS did not complete")
    end
  end

  defp assert_monotonic_generation(snapshots) do
    generated = Enum.map(snapshots, & &1.generated_bytes)
    assert generated != []
    assert generated == Enum.sort(generated)
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
