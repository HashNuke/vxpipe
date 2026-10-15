defmodule Vxpipe.Providers.MorseCodeApi.TTSSocketReuseTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, TTS, TTSSession}

  test "two utterances share one websocket connection with per-context terminals" do
    server = start_supervised!({TestSpeechWireServer, owner: self()})

    origin =
      server
      |> TestSpeechWireServer.endpoint()
      |> URI.new!()
      |> Map.put(:path, nil)
      |> Map.put(:scheme, "http")
      |> URI.to_string()

    assert {:ok, endpoint} = Endpoint.new(origin, allow_http?: true)
    assert {:ok, config} = TTS.new([api_key: "synthetic"], endpoint)
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [model: "morse_v1", voice: "morse", sample_rate: 16_000],
               private: [config: config]
             )

    assert_receive {:speech_wire_connected, peer}, 1_000
    assert %Event{kind: :ready, readiness: :initialized} = next_event(session)

    assert {:ok, %{ref: first} = first_handle} = Session.speak(session, "SOS")
    first_context = assert_open(peer, "SOS")
    assert %Event{kind: :input_submitted, request_ref: ^first} = next_event(session)
    complete_utterance(session, peer, first, first_context, <<1, 0, 2, 0>>)
    assert :ok = Session.settle_output(session, first_handle, 1)

    assert {:ok, %{ref: second} = _handle} = Session.speak(session, "T")
    second_context = assert_open(peer, "T")
    refute second_context == first_context
    assert %Event{kind: :input_submitted, request_ref: ^second} = next_event(session)
    complete_utterance(session, peer, second, second_context, <<3, 0>>)

    refute_receive {:speech_wire_connected, _other}, 20

    assert :ok = TTSSession.close(Session.provider(session))
    assert_receive {:speech_wire_frame, ^peer, :text, goodbye}, 1_000
    assert JSON.decode!(goodbye) == %{"close_socket" => true}
    assert_receive {:speech_wire_closed, ^peer}, 1_000
  end

  defp complete_utterance(session, peer, request, context, pcm) do
    send(
      peer,
      {:send,
       [
         {:text,
          JSON.encode!(%{
            "audio" => Base.encode64(pcm),
            "isFinal" => false,
            "contextId" => context
          })},
         {:text, JSON.encode!(%{"audio" => nil, "isFinal" => true, "contextId" => context})}
       ]}
    )

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, request_ref: ^request, payload: ^pcm} = audio},
                   1_000

    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)
    assert %Event{kind: :completed, request_ref: ^request} = next_event(session)
  end

  defp assert_open(peer, text) do
    assert_receive {:speech_wire_frame, ^peer, :text, init}, 500
    assert %{"text" => " ", "context_id" => context} = JSON.decode!(init)
    assert_receive {:speech_wire_frame, ^peer, :text, body}, 500
    assert %{"text" => ^text, "context_id" => ^context} = JSON.decode!(body)
    assert_receive {:speech_wire_frame, ^peer, :text, flush}, 500
    assert %{"context_id" => ^context, "flush" => true} = JSON.decode!(flush)
    assert_receive {:speech_wire_frame, ^peer, :text, close}, 500
    assert %{"context_id" => ^context, "close_context" => true} = JSON.decode!(close)
    context
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
