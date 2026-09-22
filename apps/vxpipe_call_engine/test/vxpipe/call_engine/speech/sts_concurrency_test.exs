defmodule Vxpipe.CallEngine.Speech.STSConcurrencyTest do
  @moduledoc """
  Deterministic tiny load: ten concurrent agent STS calls complete with
  bounded work and no cross-call leakage. Five use provider transcription,
  five use STS plus agent-output STT.
  """
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.TestAudioOutputSink

  @words [
    "ALPHA",
    "BRAVO",
    "CHARLIE",
    "DELTA",
    "ECHO",
    "FOXTROT",
    "GOLF",
    "HOTEL",
    "INDIA",
    "JULIET"
  ]

  test "ten concurrent Morse STS calls settle with isolated transcripts" do
    jobs =
      @words
      |> Enum.with_index()
      |> Enum.map(fn {word, index} ->
        %{id: index, word: word, output_stt?: rem(index, 2) == 1}
      end)

    results =
      Task.async_stream(jobs, &run_call/1, max_concurrency: 10, timeout: 30_000)
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> flunk("call task exited: #{inspect(reason)}")
      end)

    assert length(results) == 10

    Enum.each(results, fn %{word: word, input: input, agent: agent} ->
      assert input == word
      assert agent == "RECEIVED #{word}"
    end)

    words = Enum.map(results, & &1.word)
    assert Enum.uniq(words) == words
  end

  defp run_call(%{id: id, word: word, output_stt?: output_stt?}) do
    human = "human-load-#{id}"
    agent = "agent-load-#{id}"
    {:ok, sink} = TestAudioOutputSink.start_link(observer: self())
    {:ok, private_init} = PrivateInit.open([], 5_000)
    {:ok, output_private} = PrivateInit.open([], 5_000)

    tree_options =
      [
        owner: self(),
        agent_id: agent,
        human_id: human,
        provider: provider_options(output_stt?),
        provider_private: private_init,
        sink: sink,
        frame_identity: %{},
        caller_source: :sts,
        policy: unrestricted()
      ] ++ output_stt_tree_options(output_stt?, output_private)

    {:ok, tree} = Tree.start_link(tree_options)

    try do
      capability = Tree.capability(tree)
      true = is_pid(capability)
      assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
      push_morse(capability, human, word)

      assert_receive {:vxpipe_sts_input_transcript, ^capability, ^human, ^word, _turn, _final,
                      _interval},
                     5_000

      assert_receive {:vxpipe_sts_turn_started, ^capability, ^agent, _turn}, 5_000
      assert_receive {:test_audio_output_finish, ^sink, _turn}, 5_000
      TestAudioOutputSink.playback_progress(sink, 20, 1_020)
      TestAudioOutputSink.playback_completed(sink)

      assert_receive {:vxpipe_sts_agent_transcript, ^capability, ^agent, agent_text, _turn, 20,
                      _interval},
                     5_000

      assert_receive {:vxpipe_sts_turn_completed, ^capability, ^agent, _turn}, 5_000

      %{id: id, word: word, input: word, agent: agent_text}
    after
      _ = Supervisor.stop(tree, :normal, 5_000)
      _ = GenServer.stop(sink, :normal, 5_000)
      PrivateInit.close(private_init)
      PrivateInit.close(output_private)
    end
  end

  defp provider_options(true),
    do: {Vxpipe.Providers.MorseCode.STSSession, [output_transcript: false]}

  defp provider_options(false), do: {Vxpipe.Providers.MorseCode.STSSession, []}

  defp output_stt_tree_options(true, output_private) do
    [output_stt: {Vxpipe.Providers.MorseCode.STTSession, []}, output_stt_private: output_private]
  end

  defp output_stt_tree_options(false, output_private) do
    _ = output_private
    []
  end

  defp push_morse(capability, human, text) do
    {:ok, config} = Config.new([])
    {:ok, pcm} = Encoder.encode(config, text)

    for <<chunk::binary-size(320) <- pcm>> do
      :ok = SpeechToSpeech.push_audio(capability, human, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      :ok = SpeechToSpeech.push_audio(capability, human, tail)
    end
  end

  defp unrestricted do
    %Effective{
      audio_routes: :unrestricted,
      transcript_routes: :unrestricted,
      record_audio: true,
      save_transcripts: true
    }
  end
end
