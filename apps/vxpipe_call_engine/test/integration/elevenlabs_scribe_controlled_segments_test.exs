defmodule Vxpipe.CallEngine.Integration.ElevenLabsScribeControlledSegmentsTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 90_000

  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket, ScribeTurn}
  alias Vxpipe.Providers.LiveModels

  test "manual segment settlement preserves one caller turn beyond the segment budget" do
    fixture = File.read!(LiveFixture.pcm_path())
    size = byte_size(fixture) - 64_000
    assert size > 0 and rem(size, 2) == 0
    <<phrase::binary-size(size), silence::binary>> = fixture
    assert silence == :binary.copy(<<0>>, 64_000)
    audio = :binary.copy(phrase, 10) <> silence
    assert byte_size(audio) > 20 * 32_000 and byte_size(audio) <= 25 * 32_000

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en",
               commit_strategy: :manual
             )

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ScribeSocket, :start_link,
           [[owner: self(), connection: Scribe.connection_options(config), transport_options: []]]},
        restart: :temporary
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 15_000
    assert_receive {:vxpipe_scribe_transport, ^socket, {:event, {:ready, _session_id}}}, 5_000
    turn_ref = make_ref()
    {turn, segments, ends} = stream(socket, ScribeTurn.new(turn_ref), audio, 0, [])
    assert segments == 1
    assert ends == []

    # The supplied boundary exercises recognition settlement; no acoustic model is claimed.
    assert {:ok, turn, actions} = ScribeTurn.end_turn(turn)
    {_turn, segments, ends} = execute(socket, turn, actions, segments, ends)
    assert segments == 2
    assert length(ends) == 1
    assert Enum.all?(ends, fn {reference, _text} -> reference == turn_ref end)
    [{_reference, text}] = ends
    fixture_word? = String.downcase(text) =~ "telescope"

    assert fixture_word?,
           "Scribe's cumulative transcript did not preserve the public fixture word"

    IO.puts(
      "Scribe controlled manual segments: 2; caller turn ends: 1; public fixture word: present"
    )
  end

  defp stream(_socket, turn, "", segments, ends), do: {turn, segments, ends}

  defp stream(socket, turn, audio, segments, ends) do
    size = min(byte_size(audio), 3_200)
    <<chunk::binary-size(size), rest::binary>> = audio
    assert {:ok, turn, actions} = ScribeTurn.push_audio(turn, chunk)
    {turn, segments, ends} = execute(socket, turn, actions, segments, ends)
    stream(socket, turn, rest, segments, ends)
  end

  defp execute(_socket, turn, [], segments, ends), do: {turn, segments, ends}

  defp execute(socket, turn, [{:audio, audio} | actions], segments, ends) do
    assert :ok = ScribeSocket.send_audio(socket, audio)
    reference = make_ref()
    Process.send_after(self(), {:audio_pace, reference}, div(byte_size(audio), 32))
    turn = await_pace(socket, turn, reference, System.monotonic_time(:millisecond) + 1_000)
    execute(socket, turn, actions, segments, ends)
  end

  defp execute(socket, turn, [:commit | actions], segments, ends) do
    assert :ok = ScribeSocket.commit(socket)
    {turn, settled} = await_commit(socket, turn, System.monotonic_time(:millisecond) + 15_000)
    execute(socket, turn, settled ++ actions, segments + 1, ends)
  end

  defp execute(socket, turn, [{:transcript, _ref, _text} | actions], segments, ends),
    do: execute(socket, turn, actions, segments, ends)

  defp execute(socket, turn, [{:turn_ended, ref, text} | actions], segments, ends),
    do: execute(socket, turn, actions, segments, ends ++ [{ref, text}])

  defp await_pace(socket, turn, reference, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Scribe manual input pacing exceeded its deadline"

    receive do
      {:audio_pace, ^reference} ->
        turn

      {:vxpipe_scribe_transport, ^socket, {:event, {:partial, text}}} ->
        assert {:ok, turn, _events} = ScribeTurn.partial(turn, text)
        await_pace(socket, turn, reference, deadline)

      {:vxpipe_scribe_transport, ^socket, _unexpected} ->
        flunk("Scribe returned an unexpected event before manual commit")
    after
      remaining -> flunk("Scribe manual input pacing acknowledgement was missing")
    end
  end

  defp await_commit(socket, turn, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Scribe did not settle its requested manual segment"

    receive do
      {:vxpipe_scribe_transport, ^socket, {:event, {:partial, text}}} ->
        assert {:ok, turn, _events} = ScribeTurn.partial(turn, text)
        await_commit(socket, turn, deadline)

      {:vxpipe_scribe_transport, ^socket, {:event, {:segment, text}}} ->
        assert {:ok, turn, events} = ScribeTurn.committed(turn, text)
        {turn, events}

      {:vxpipe_scribe_transport, ^socket, _unexpected} ->
        flunk("Scribe failed while settling a requested manual segment")
    after
      remaining -> flunk("Scribe did not acknowledge the requested manual segment")
    end
  end
end
