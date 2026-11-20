defmodule Vxpipe.Providers.ElevenLabs.ScribeProfileSessionTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, DiagnosticSubscription, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

  for wrapped <- [false, true] do
    test "profile query with capture preserves existing #{if wrapped, do: "wrapped", else: "direct"} speech" do
      {session, wire} =
        start_session(unquote(wrapped), %{
          "model_id" => "scribe_v2_realtime",
          "commit_strategy" => "vad"
        })

      assert :ok = Session.push_audio(session, <<1, 0>>)
      assert_receive {:scribe_audio, ^wire, <<1, 0>>}

      {:ok, handoff} =
        CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

      assert :ok = DiagnosticSubscription.request_profile(session, handoff)
      canonical = session.generation

      inner =
        if unquote(wrapped), do: :sys.get_state(Session.provider(session)).inner, else: session

      provider = inner.generation
      assert {:provider_profile, ^canonical, ^provider, profile} = packet(handoff)

      assert profile.acknowledged == %{
               "model_id" => "scribe_v2_realtime",
               "commit_strategy" => "vad"
             }

      assert "sample_rate" in profile.missing
      assert :ok = Session.push_audio(session, <<2, 0>>)
      assert_receive {:scribe_audio, ^wire, <<2, 0>>}

      Wire.deliver_frame(
        wire,
        JSON.encode!(%{"message_type" => "committed_transcript", "text" => "still speaking"})
      )

      _ = event(session, :speech_started)
      assert event(session, :transcript).text == "still speaking"
      refute_received {:scribe_started, _}
      refute_received {:scribe_observing, _, _}
    end
  end

  for wrapped <- [false, true] do
    test "manual #{if wrapped, do: "wrapped", else: "direct"} query is explicitly unsupported" do
      {session, wire} = start_session(unquote(wrapped), %{"commit_strategy" => "manual"}, :manual)

      {:ok, handoff} =
        CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

      assert :ok = DiagnosticSubscription.request_profile(session, handoff)
      canonical = session.generation
      assert {:provider_profile, ^canonical, _provider, :unsupported} = packet(handoff)
      assert :ok = Session.push_audio(session, :binary.copy(<<7, 0>>, 2_048))
      assert_receive {:scribe_audio, ^wire, _}, 1_000
    end

    test "profile query preserves an existing #{if wrapped, do: "wrapped", else: "direct"} observation" do
      {session, wire} =
        start_session(unquote(wrapped), %{
          "model_id" => "scribe_v2_realtime",
          "commit_strategy" => "vad"
        })

      {:ok, capture} =
        CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

      assert :ok = Channel.observe(session, capture)
      assert_receive {:scribe_observing, ^wire, token}
      assert token == capture.token

      {:ok, query} =
        CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

      assert :ok = DiagnosticSubscription.request_profile(session, query)
      assert {:provider_profile, _, _, _} = packet(query)
      assert CaptureHandoff.current?(capture)

      inner =
        if unquote(wrapped), do: :sys.get_state(Session.provider(session)).inner, else: session

      assert :sys.get_state(:sys.get_state(Channel.address(inner)).producer).diagnostic_handoff.token ==
               capture.token

      assert :ok = Session.push_audio(session, <<7, 0>>)
      assert_receive {:scribe_audio, ^wire, <<7, 0>>}
      refute_received {:scribe_observing, _, _}
    end
  end

  defp start_session(wrapped, echoes, strategy \\ :vad) do
    tree = start_supervised!({CapabilityTree, owner: self()})
    {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: strategy)

    private = [
      config: config,
      wire_module: Wire,
      wire_options: [observer: self()],
      activity_options: [
        load: fn -> {:ok, :fixture} end,
        classify: fn _, stream, pcm ->
          count = div(byte_size(pcm), 1_024)
          {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.8, count)}
        end
      ]
    ]

    options =
      if wrapped do
        [
          provider: Vxpipe.CallEngine.Speech.ConversationalSTT,
          options: [provider: STTSession, options: [commit_strategy: strategy], vad: false],
          private: [
            recognizer: STTSession,
            recognizer_options: [commit_strategy: strategy],
            recognizer_private: private
          ]
        ]
      else
        [provider: STTSession, options: [commit_strategy: strategy], private: private]
      end

    {:ok, session, :starting} = Session.start(CapabilityTree.scope(tree), options)
    assert_receive {:scribe_started, wire}

    Wire.deliver_frame(
      wire,
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "synthetic",
        "config" => echoes
      })
    )

    _ = event(session, :ready)
    {session, wire}
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end

  defp packet(handoff) do
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message, 1_000
    assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)
    :ok = CaptureHandoff.release(handoff, charge, :processed)
    packet
  end
end
