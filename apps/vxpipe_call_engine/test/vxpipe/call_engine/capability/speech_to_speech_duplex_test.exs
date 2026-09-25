defmodule Vxpipe.CallEngine.Capability.SpeechToSpeechDuplexTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession, as: DuplexSTS

  @human "human1"
  @agent "agent1"

  test "one caller audio turn produces one segmented reply, transcript and usage" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), usage_context: sts_usage_context())

    push_morse(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      identity: %{participant_id: @human},
                      event: %{kind: :input_transcript, text: "HI", final: true}
                    }}

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
    advance_until_idle(capability)
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn, 20,
                    _interval, _}

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}

    assert_receive {:vxpipe_usage_observations, ^capability, [observation | _]}
    assert observation.capability == :speech_to_speech
    assert observation.measurement.unit == :milliseconds
    refute_received {:vxpipe_send_text, _, _, _}
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
    TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED HI", ^turn, 20,
                    _, _},
                   5_000
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

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, reply_turn, _}
    assert reply_turn != tool_turn
    advance_until_idle(capability)
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, "RECEIVED OK", _, _, _, _}
  end

  test "a non-Morse-encodable tool result still produces a spoken reply" do
    {_tree, capability, _sink} = start_capability(policy: unrestricted())

    assert :ok = SpeechToSpeech.push_text(capability, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref, turn_ref: tool_turn}}}

    assert :ok = SpeechToSpeech.send_tool_result(capability, call_ref, %{"ok" => true})

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, reply_turn, _}
    assert reply_turn != tool_turn
    advance_until_idle(capability)
    complete_playback(20)

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

    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, _turn, _}
    advance_until_idle(capability)
    complete_playback(20)

    assert_receive {:vxpipe_sts_agent_transcript, ^capability, @agent, text, _, _, _, _}
    assert String.starts_with?(text, "RECEIVED ")
    assert byte_size(text) <= 40
  end

  test "caller onset leaves a provider-owned output playing, but room fences still cut it" do
    {_tree, capability, _sink} =
      start_capability(policy: unrestricted(), provider: {DuplexSTS, [yield?: false]})

    push_morse(capability, "HI")
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, turn, _}
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
      # Let the capability process sink acknowledgements before the next frame.
      _ = :sys.get_state(capability)

      if :sys.get_state(provider).output == nil do
        {:halt, :ok}
      else
        :ok = DuplexSTS.advance(provider, 20)
        {:cont, :ok}
      end
    end)
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

  defp complete_playback(played_ms) do
    assert_receive {:test_audio_output_finish, sink, _turn}, 5_000
    TestAudioOutputSink.playback_progress(sink, played_ms, played_ms + 1_000)
    TestAudioOutputSink.playback_completed(sink)
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
