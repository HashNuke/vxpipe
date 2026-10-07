defmodule Vxpipe.CallEngine.Capability.SpeechToSpeechDuplexTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.Output
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession, as: DuplexSTS

  @human "human1"
  @agent "agent1"

  test "a reply with an inter-word gap produces two admitted turns in order" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, unit_duration_ms: 150]}
      )

    push_morse(capability, "AB", unit_duration_ms: 150)

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "AB", final: true}}}

    transcripts = collect_transcripts(capability, sink, 2)
    turns = transcripts |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    assert length(turns) == 2
    assert Enum.map(transcripts, &elem(&1, 1)) == ["RECEIVED", " AB"]
  end

  test "one caller audio turn produces one segmented reply, transcript and usage" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      identity: %{participant_id: @human},
                      event: %{kind: :input_transcript, text: "HI", final: true}
                    }}

    turn = await_turn_started(capability)
    advance_until_idle(capability)
    played_ms = playback_duration(capability)
    complete_playback(played_ms)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn,
                    ^played_ms, _interval, _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}

    assert_receive {:vxpipe_usage_observations, ^capability, [observation | _]}
    assert observation.capability == :speech_to_speech
    assert observation.measurement.unit == :milliseconds
    refute_received {:vxpipe_send_text, _, _, _}
  end

  test "the Morse duplex provider fences at the last played word" do
    {_tree, capability, sink} = start_capability(policy: unrestricted())
    push_morse(capability, "HI")
    turn = await_turn_started(capability)
    advance_until_idle(capability)

    output = :sys.get_state(capability).active_output

    {_start_ms, first_end_ms, "RECEIVED"} =
      Enum.find(output.fragments, fn {_start_ms, _end_ms, text} -> text == "RECEIVED" end)

    assert_receive {:test_audio_output_finish, ^sink, _turn}, 5_000

    assert :ok =
             TestAudioOutputSink.playback_progress(
               sink,
               first_end_ms,
               playback_duration(capability)
             )

    assert {:ok, ^first_end_ms} = SpeechToSpeech.interrupt(capability)

    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, ^first_end_ms,
                    {:aligned_prefix, "RECEIVED", _interval}, _}
  end

  test "the realtime clock speaks without any external ticks" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :realtime, unit_duration_ms: 20]}
      )

    push_morse(capability, "HI", unit_duration_ms: 20)

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", final: true}}},
                   5_000

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}, 5_000
    assert_receive {:test_audio_output, sink, _frame}, 5_000
    assert_receive {:test_audio_output_finish, ^sink, _turn}, 10_000
    played_ms = playback_duration(capability)
    TestAudioOutputSink.playback_progress(sink, played_ms, played_ms)
    TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn,
                    ^played_ms, _, _},
                   5_000
  end

  test "a scripted Morse expiry while idle reseeds without speaking until new input" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, scripted_closes?: true]}
      )

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", final: true}}},
                   1_000

    publish_history(capability, {:caller, "HI"})
    first_turn = await_turn_started(capability)
    advance_until_idle(capability)
    played_ms = playback_duration(capability)
    complete_playback(played_ms)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^first_turn,
                    ^played_ms, _, _},
                   1_000

    publish_history(capability, {:agent, "RECEIVED HI"})

    provider = Session.provider(:sys.get_state(capability).session)
    _ = :sys.get_state(capability)
    monitor = Process.monitor(provider)

    assert {:ok, %{seeded_history: seeded, resume?: false}} =
             DuplexSTS.script_close(provider, :expired)

    assert Enum.map(seeded, & &1["role"]) == ["user", "assistant"]
    assert Enum.map(seeded, fn entry -> hd(entry["content"])["text"] end) == ["HI", "RECEIVED HI"]
    refute_received {:DOWN, ^monitor, :process, ^provider, _}
    refute_received {:vxpipe_sts_turn_started, ^capability, @agent, _, _}

    assert :ok = SpeechToSpeech.push_text(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", final: true}}},
                   1_000

    publish_history(capability, {:caller, "HI"})

    assert is_reference(await_turn_started(capability))
  end

  test "a scripted Morse expiry seeds published caller text and resumes an unanswered turn" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, scripted_closes?: true]}
      )

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", final: true}}},
                   1_000

    publish_history(capability, {:caller, "HI"})

    provider = Session.provider(:sys.get_state(capability).session)
    _ = :sys.get_state(capability)

    assert {:ok, %{seeded_history: seeded, resume?: true}} =
             DuplexSTS.script_close(provider, :expired)

    assert seeded == [
             %{
               "type" => "message",
               "role" => "user",
               "content" => [%{"type" => "input_text", "text" => "HI"}]
             }
           ]

    turn = await_turn_started(capability)
    advance_until_idle(capability)
    played_ms = playback_duration(capability)
    complete_playback(played_ms)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED LINE CUT OUT HI",
                    ^turn, ^played_ms, _, _},
                   1_000
  end

  test "a scripted Morse connection loss during output starts a new spoken burst" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, scripted_closes?: true]}
      )

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", final: true}}},
                   1_000

    publish_history(capability, {:caller, "HI"})
    first_turn = await_turn_started(capability)
    provider = Session.provider(:sys.get_state(capability).session)

    assert Vxpipe.CallEngine.Speech.Duplex.OutputSegmenter.burst?(
             :sys.get_state(provider).segmenter
           )

    assert {:ok, %{seeded_history: [_caller], resume?: true}} =
             DuplexSTS.script_close(provider, :connection_lost)

    assert_receive {:test_audio_output_finish, ^sink, _}, 1_000
    TestAudioOutputSink.playback_progress(sink, 20, 20)
    TestAudioOutputSink.playback_completed(sink)

    second_turn = await_turn_started(capability)
    assert second_turn != first_turn
    assert :sys.get_state(capability).active_output.provider_turn == second_turn
    advance_until_idle(capability)
    played_ms = playback_duration(capability)
    complete_playback(played_ms)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED LINE CUT OUT HI",
                    ^second_turn, ^played_ms, _, _},
                   1_000
  end

  test "a second scripted Morse close fails the capability instead of reseeding again" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, scripted_closes?: true]}
      )

    provider = Session.provider(:sys.get_state(capability).session)
    monitor = Process.monitor(provider)
    assert {:ok, %{resume?: false}} = DuplexSTS.script_close(provider, :expired)
    assert {:error, :reseed_failed} = DuplexSTS.script_close(provider, :connection_lost)
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :reseed_failed}}, 1_000
    assert_receive {:vxpipe_sts_unavailable, ^capability, :reseed_failed}, 1_000
  end

  test "Morse scripted closes are unavailable without the local test option" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    provider = Session.provider(:sys.get_state(capability).session)
    assert {:error, :unsupported_operation} = DuplexSTS.script_close(provider, :expired)
    assert :ok = SpeechToSpeech.push_text(capability, "HI")
  end

  test "a Morse tool already delegated to the room completes after scripted reseed" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, scripted_closes?: true]}
      )

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref}}},
                   1_000

    provider = Session.provider(:sys.get_state(capability).session)
    assert {:ok, %{resume?: true}} = DuplexSTS.script_close(provider, :connection_lost)
    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})

    turns = collect_transcripts(capability, sink, 2)
    assert Enum.map(turns, &elem(&1, 1)) == ["RECEIVED LINE CUT OUT", "RECEIVED OK TRUE"]
  end

  test "a held Morse tool result remains queued across scripted reseed" do
    {_tree, capability, sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, scripted_closes?: true]}
      )

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref}}},
                   1_000

    assert :ok = SpeechToSpeech.hold(capability)
    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})
    provider = Session.provider(:sys.get_state(capability).session)
    assert {:ok, %{resume?: true}} = DuplexSTS.script_close(provider, :expired)
    assert :ok = SpeechToSpeech.release(capability)

    turns = collect_transcripts(capability, sink, 2)
    assert Enum.map(turns, &elem(&1, 1)) == ["RECEIVED OK TRUE", "RECEIVED LINE CUT OUT"]
  end

  test "a delegated tool call result reopens a spoken reply" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{
                      event: %{
                        kind: :tool_call,
                        call_ref: call_ref,
                        turn_ref: tool_turn,
                        tool_name: "echo",
                        arguments: %{"text" => "hi"}
                      }
                    }}

    refute_received {:vxpipe_sts_turn_started, ^capability, _, _, _}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, "ok")

    reply_turn = await_turn_started(capability)
    assert reply_turn != tool_turn
    advance_until_idle(capability)
    complete_playback(playback_duration(capability))

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED OK", _, _, _, _}
  end

  test "mute hold keeps a tool and provider session, then speaks the tool result after release" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())
    provider = Session.provider(:sys.get_state(capability).session)
    monitor = Process.monitor(provider)

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref}}}

    assert :ok = SpeechToSpeech.hold(capability)
    {:ok, pcm} = encode("HI", [])
    <<first::binary-size(320), _::binary>> = pcm
    assert {:error, :held} = SpeechToSpeech.push_audio(capability, @human, first)
    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, "OK")
    refute_received {:vxpipe_sts_turn_started, ^capability, @agent, _, _}

    assert :ok = SpeechToSpeech.release(capability)
    assert Session.provider(:sys.get_state(capability).session) == provider
    refute_received {:DOWN, ^monitor, :process, ^provider, _}
    assert :sys.get_state(provider).hold_log == [{:hold, :started}, {:hold, :ended}]

    _turn = await_turn_started(capability)
    advance_until_idle(capability)
    complete_playback(playback_duration(capability))
    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED OK", _, _, _, _}
  end

  test "a non-Morse-encodable tool result still produces a spoken reply" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref, turn_ref: tool_turn}}}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})

    reply_turn = await_turn_started(capability)
    assert reply_turn != tool_turn
    advance_until_idle(capability)
    complete_playback(playback_duration(capability))

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED OK TRUE", _, _,
                    _, _}
  end

  test "a long tool result is truncated into a bounded Morse reply" do
    {_tree, capability, _sink} =
      start_capability(
        policy: unrestricted(),
        provider: {DuplexSTS, [clock: :manual, maximum_text_bytes: 40]}
      )

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref}}}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, String.duplicate("Z", 400))

    _turn = await_turn_started(capability)
    advance_until_idle(capability)
    complete_playback(playback_duration(capability))

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, text, _, _, _, _}
    assert String.starts_with?(text, "RECEIVED ")
    assert byte_size(text) <= 40
  end

  test "caller onset leaves a provider-owned output playing, but room fences still cut it" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), provider: {DuplexSTS, [yield?: false]})

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}, 5_000
    assert :sys.get_state(capability).active_output != nil

    # Caller onset during the reply must not fence a provider-owned output.
    push_morse(capability, "NO")
    refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _, _}
    assert :sys.get_state(capability).active_output != nil

    # A policy denial still fences the output.
    assert :ok = SpeechToSpeech.apply_policy(capability, deny_audio(@agent, @human))
    assert_receive {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _, _}
  end

  defp advance_until_idle(capability) do
    provider = Session.provider(:sys.get_state(capability).session)

    Enum.reduce_while(1..2_000, :ok, fn _, :ok ->
      # Preserve one real sink delivery per scripted clock advance.
      TestAudioOutputSink.await_delivery(capability)
      drain_audio()

      provider_state = :sys.get_state(provider)

      if Output.idle?(provider_state.timeline) and provider_state.segments == %{} do
        {:halt, :ok}
      else
        TestAudioOutputSink.await_delivery(capability)
        :ok = DuplexSTS.advance(provider, 20)
        {:cont, :ok}
      end
    end)
  end

  defp await_turn_started(capability, remaining \\ 2_000)

  defp await_turn_started(_capability, 0), do: flunk("no agent turn started")

  defp await_turn_started(capability, remaining) do
    receive do
      {:vxpipe_sts_turn_started, ^capability, @agent, turn, _} ->
        turn

      {:vxpipe_sts_input_event, ^capability, _} ->
        await_turn_started(capability, remaining)

      {:vxpipe_sts_speech_started, ^capability, _, _} ->
        await_turn_started(capability, remaining)

      {:test_audio_output, _, _} ->
        await_turn_started(capability, remaining)

      {:vxpipe_sts_tool_event, ^capability, _, _} ->
        await_turn_started(capability, remaining)
    after
      0 ->
        provider = Session.provider(:sys.get_state(capability).session)
        TestAudioOutputSink.await_delivery(capability)
        :ok = DuplexSTS.advance(provider, 20)
        await_turn_started(capability, remaining - 1)
    end
  end

  defp drain_audio do
    receive do
      {:test_audio_output, _, _} -> drain_audio()
    after
      0 -> :ok
    end
  end

  # Drive the manual clock until `expected` agent transcripts arrive, completing
  # each output's playback so the room admits the next queued burst.
  defp collect_transcripts(capability, sink, expected, acc \\ [], remaining \\ 4_000)

  defp collect_transcripts(_capability, _sink, _expected, acc, 0), do: Enum.reverse(acc)

  defp collect_transcripts(capability, sink, expected, acc, remaining) do
    if length(acc) >= expected do
      Enum.reverse(acc)
    else
      provider = Session.provider(:sys.get_state(capability).session)

      receive do
        {:vxpipe_sts_agent_transcript, ^capability, @agent, text, turn, _played, _interval, _} ->
          collect_transcripts(capability, sink, expected, [{turn, text} | acc], remaining)

        {:test_audio_output_finish, ^sink, _turn} ->
          played_ms = playback_duration(capability)
          TestAudioOutputSink.playback_progress(sink, played_ms, played_ms)
          TestAudioOutputSink.playback_completed(sink)
          collect_transcripts(capability, sink, expected, acc, remaining)

        {:test_audio_output, _, _} ->
          collect_transcripts(capability, sink, expected, acc, remaining)

        {:vxpipe_sts_turn_started, ^capability, @agent, _, _} ->
          collect_transcripts(capability, sink, expected, acc, remaining)

        {:vxpipe_sts_turn_completed, ^capability, @agent, _, _} ->
          collect_transcripts(capability, sink, expected, acc, remaining)
      after
        0 ->
          TestAudioOutputSink.await_delivery(capability)
          :ok = DuplexSTS.advance(provider, 20)
          collect_transcripts(capability, sink, expected, acc, remaining - 1)
      end
    end
  end

  defp start_capability(options) do
    alias Vxpipe.CallEngine.Speech.PrivateInit

    startup_timeout_ms = 5_000
    owner = Keyword.get(options, :owner, self())
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {:ok, private_init} =
      PrivateInit.open(Keyword.get(options, :provider_private, []), startup_timeout_ms)

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {SpeechToSpeech.Tree,
           [
             owner: owner,
             agent_id: @agent,
             human_id: @human,
             provider:
               Keyword.get(
                 options,
                 :provider,
                 {Vxpipe.Providers.MorseCode.DuplexSTSSession, [clock: :manual]}
               ),
             provider_private: private_init,
             sink: sink,
             frame_identity: %{},
             caller_source: Keyword.get(options, :caller_source, :sts),
             policy: Keyword.fetch!(options, :policy),
             usage_context: Keyword.get(options, :usage_context)
           ]},
          id: make_ref()
        )
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert is_pid(capability)

    if owner == self() do
      assert_receive {:vxpipe_sts_ready, ^capability}, startup_timeout_ms
    end

    {tree, capability, sink}
  end

  defp push_morse(capability, text, encode_options \\ []) do
    {:ok, pcm} = encode(text, encode_options)

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = SpeechToSpeech.push_audio(capability, @human, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = SpeechToSpeech.push_audio(capability, @human, tail)
    end
  end

  defp encode(text, options) do
    {:ok, config} = Config.new(options)
    Encoder.encode(config, text)
  end

  defp publish_history(capability, entry) do
    send(capability, {:vxpipe_sts_published_history, self(), entry})
    _ = :sys.get_state(capability)
  end

  defp complete_playback(played_ms) do
    assert_receive {:test_audio_output_finish, sink, _turn}, 5_000
    TestAudioOutputSink.playback_progress(sink, played_ms, played_ms + 1_000)
    TestAudioOutputSink.playback_completed(sink)
  end

  defp playback_duration(capability) do
    capability_state = :sys.get_state(capability)
    provider = Session.provider(capability_state.session)
    provider_state = :sys.get_state(provider)
    burst = Map.fetch!(provider_state.bursts.bursts, capability_state.active_output.provider_turn)
    Map.fetch!(provider_state.segmenter.outputs, burst.seg_ref).duration_ms
  end

  defp deny_audio(source, _recipient) do
    %Effective{
      audio_routes: %{source => MapSet.new([])},
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end

  defp unrestricted do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end

  defp sts_usage_context do
    assert {:ok, provider} =
             Vxpipe.CallEngine.Usage.ProviderContext.new(
               name: "morse_code_duplex",
               integration_id: "local-sts-duplex",
               model: "morse-conversation"
             )

    [
      call_id: "call-sts-duplex-usage",
      participant_id: @agent,
      activation_id: "activation-sts-duplex",
      provider: provider,
      tenant_id: "tenant-sts-duplex",
      room_id: "room-sts-duplex",
      incarnation_id: "incarnation-sts-duplex"
    ]
  end
end
