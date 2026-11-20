defmodule Vxpipe.CallEngine.Capability.TextToSpeechDiagnosticsTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Tree
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.{SpeechTTSUsageProbe, TestAudioOutputSink, TextToSpeechRequest}

  test "stop evidence belongs to the new human and precedes provider cancellation" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(provider_private: [observer: self(), hold_cancel?: true])
    assert {:ok, _, :ready} = await_ready(capability)
    old = request("old-human-turn", sink)
    assert :ok = TextToSpeech.synthesize(capability, old)
    assert_receive {:usage_probe_submitted, reference, _}
    assert_receive {:test_audio_output, ^sink, _}
    assert_receive {:usage_probe_audio_credited, ^reference, _}
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}

    assert {:ok, handoff} =
             CaptureHandoff.new(self(),
               settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__)
             )

    generation = make_ref()
    turn_ref = make_ref()
    context = {handoff, generation, turn_ref, "new-human-turn", "new-command"}
    parent = self()

    start_supervised!(
      {Task,
       fn ->
         send(parent, {:interrupted, TextToSpeech.interrupt_observed(capability, context)})
       end}
    )

    assert_receive {:usage_probe_cancel_held, provider, ^reference}, 500
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message

    assert {:ok,
            {:barge_in_playback, ^generation, ^turn_ref, "new-human-turn", "new-command",
             {"agent-semantic", "human-test", "connection-test", "old-human-turn", "command-test",
              "output-test"}, started, requested, stopped, nil}, charge} =
             CaptureHandoff.message(handoff, message)

    assert started <= requested
    assert requested <= stopped
    assert stopped <= System.monotonic_time(:microsecond)
    refute_receive {:interrupted, _}, 0
    :ok = CaptureHandoff.release(handoff, charge, :processed)
    send(provider, :release_usage_probe_cancel)
    assert_receive {:interrupted, {:ok, [{^old, 0}]}}, 500
  end

  @tag :capture_log
  test "missing stop acknowledgement preserves failure semantics without inventing a turn" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(output_request_timeout: 10)
    assert {:ok, _, :ready} = await_ready(capability)
    old = request("old-turn", sink)
    assert :ok = TextToSpeech.synthesize(capability, old)
    assert_receive {:usage_probe_submitted, reference, _}
    assert_receive {:test_audio_output, ^sink, _}
    assert_receive {:usage_probe_audio_credited, ^reference, _}
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}
    :ok = TestAudioOutputSink.defer_interrupt(sink, true)

    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    generation = make_ref()
    context = {handoff, generation, make_ref(), "new-turn", "new-command"}
    monitor = Process.monitor(capability)
    assert {:error, :unavailable} = TextToSpeech.interrupt_observed(capability, context)
    assert_receive {:DOWN, ^monitor, :process, ^capability, :audio_output_failed}
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)
    assert elem(packet, 8) == nil
    assert elem(packet, 9) == :stop_unavailable

    state =
      Vxpipe.CallEngine.Diagnostics.LiveReport.new(%{
        generation: generation,
        clock_id: "clock",
        origin_us: 0
      })

    assert {:ok, state} = Vxpipe.CallEngine.Diagnostics.LiveReport.observe(state, packet)
    assert Vxpipe.CallEngine.Diagnostics.LiveReport.reports(state) == []
    :ok = CaptureHandoff.release(handoff, charge, :processed)
    :ok = TestAudioOutputSink.complete_interrupt(sink)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert {:error, :unavailable} = TextToSpeech.synthesize(capability, old)
  end

  test "stale callbacks are ignored and duplicate starts retain the first timestamp" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability([])
    assert {:ok, _, :ready} = await_ready(capability)
    old = request("old-turn", sink)
    assert :ok = TextToSpeech.synthesize(capability, old)
    assert_receive {:usage_probe_submitted, reference, _}
    assert_receive {:test_audio_output, ^sink, _}
    assert_receive {:usage_probe_audio_credited, ^reference, _}
    send(capability, {:vxpipe_audio_playback, sink, "stale-turn", :started})
    send(capability, {:vxpipe_audio_playback, self(), old.correlation_id, :started})
    _ = :sys.get_state(capability)
    refute_received {:vxpipe_tts_playback, ^capability, _, :started}
    first_before = System.monotonic_time(:microsecond)
    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}
    first_after = System.monotonic_time(:microsecond)
    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}

    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    assert {:ok, [{^old, 0}]} =
             TextToSpeech.interrupt_observed(
               capability,
               {handoff, make_ref(), make_ref(), "new-turn", "new-command"}
             )

    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)
    assert elem(packet, 6) >= first_before
    assert elem(packet, 6) <= first_after
    assert elem(packet, 9) == nil
    :ok = CaptureHandoff.release(handoff, charge, :processed)
  end

  test "an idle capability has no playback to measure" do
    capability = start_capability([])
    assert {:ok, _, :ready} = await_ready(capability)

    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    assert {:ok, []} =
             TextToSpeech.interrupt_observed(
               capability,
               {handoff, make_ref(), make_ref(), "new-turn", "new-command"}
             )

    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert CaptureHandoff.stats(handoff).pending_count == 0
  end

  test "source replacement during sink wait cannot move evidence into the new source clock" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability([])
    assert {:ok, _, :ready} = await_ready(capability)
    old = request("old-turn", sink)
    assert :ok = TextToSpeech.synthesize(capability, old)
    assert_receive {:usage_probe_submitted, reference, _}
    assert_receive {:test_audio_output, ^sink, _}
    assert_receive {:usage_probe_audio_credited, ^reference, _}
    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}
    :ok = TestAudioOutputSink.defer_interrupt(sink, true)

    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    parent = self()

    start_supervised!(
      {Task,
       fn ->
         send(
           parent,
           {:interrupted,
            TextToSpeech.interrupt_observed(
              capability,
              {handoff, make_ref(), make_ref(), "new-turn", "new-command"}
            )}
         )
       end}
    )

    assert_receive {:test_audio_output_interrupt, ^sink, "old-turn", 0}
    :ok = CaptureHandoff.close(handoff)

    {:ok, replacement} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    assert CaptureHandoff.closed_reason(handoff) == :source_changed
    :ok = TestAudioOutputSink.complete_interrupt(sink)
    assert_receive {:interrupted, {:ok, [{^old, 0}]}}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert CaptureHandoff.stats(replacement).pending_count == 0
  end

  for scenario <- [:unstarted, :wrong_turn, :revoked, :full] do
    @tag scenario: scenario
    test "#{scenario} interruption does not fabricate available playback evidence", ctx do
      scenario = ctx.scenario
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      capability = start_capability(provider_private: [observer: self(), hold_cancel?: true])
      assert {:ok, _, :ready} = await_ready(capability)
      old = request("old-turn", sink)
      assert :ok = TextToSpeech.synthesize(capability, old)
      assert_receive {:usage_probe_submitted, reference, _}
      assert_receive {:test_audio_output, ^sink, _}
      assert_receive {:usage_probe_audio_credited, ^reference, _}

      if scenario != :unstarted do
        assert :ok = TestAudioOutputSink.playback_started(sink)
        assert_receive {:vxpipe_tts_playback, ^capability, ^old, :started}
      end

      if scenario == :wrong_turn, do: TestAudioOutputSink.playback_completed(sink)

      assert {:ok, handoff} =
               CaptureHandoff.new(self(),
                 settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
                 maximum_count: 1
               )

      if scenario == :full,
        do: assert(:ok = CaptureHandoff.offer(handoff, {:reset, 0, :partial_start, 0}))

      if scenario == :revoked, do: CaptureHandoff.close(handoff)
      context = {handoff, make_ref(), make_ref(), "new-turn", "new-command"}
      parent = self()

      start_supervised!(
        {Task,
         fn ->
           send(parent, {:interrupted, TextToSpeech.interrupt_observed(capability, context)})
         end}
      )

      assert_receive {:usage_probe_cancel_held, provider, ^reference}, 500

      if scenario in [:revoked, :full] do
        if scenario == :full do
          assert_receive {:vxpipe_diagnostic_capture, _, _, {:reset, _, _, _}, _} = queued
          {:ok, _, charge} = CaptureHandoff.message(handoff, queued)
          :ok = CaptureHandoff.release(handoff, charge, :processed)
          assert CaptureHandoff.stats(handoff).overflow == 1
        end

        refute_receive {:vxpipe_diagnostic_capture, _, _, _, _}, 0
      else
        assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
        assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)

        if scenario == :unstarted do
          assert elem(packet, 6) == nil
          assert elem(packet, 9) == :not_playing
        else
          assert elem(packet, 8) == nil
          assert elem(packet, 9) == :stop_unavailable
        end

        :ok = CaptureHandoff.release(handoff, charge, :processed)
      end

      send(provider, :release_usage_probe_cancel)
      assert_receive {:interrupted, {:ok, [{^old, 0}]}}, 500
    end
  end

  defp start_capability(options) do
    provider = Keyword.get(options, :provider, SpeechTTSUsageProbe)
    provider_private = Keyword.get(options, :provider_private, observer: self())

    {:ok, private_init} = PrivateInit.open(provider_private, 5_000)

    tree =
      try do
        tree_options =
          [
            owner: self(),
            participant_id: "agent-semantic",
            provider: {provider, []},
            provider_private: private_init,
            maximum_requests: Keyword.get(options, :maximum_requests, 1),
            usage: Keyword.get(options, :usage),
            name:
              {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, self(), make_ref()}}}
          ]
          |> maybe_put_output_request_timeout(options)

        start_supervised!({Tree, tree_options})
      after
        PrivateInit.close(private_init)
      end

    Tree.capability(tree)
  end

  defp maybe_put_output_request_timeout(tree_options, options) do
    case Keyword.fetch(options, :output_request_timeout) do
      {:ok, timeout} -> Keyword.put(tree_options, :output_request_timeout, timeout)
      :error -> tree_options
    end
  end

  defp await_ready(capability) do
    case TextToSpeech.readiness(capability) do
      {:ok, _resource, :preparing} ->
        _ = :sys.get_state(capability)
        await_ready(capability)

      result ->
        result
    end
  end

  defp request(correlation_id, sink) do
    %TextToSpeechRequest{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-semantic",
      source_participant_id: "human-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: correlation_id,
      output_id: "output-test",
      text: "E",
      output_sink: sink
    }
  end
end
