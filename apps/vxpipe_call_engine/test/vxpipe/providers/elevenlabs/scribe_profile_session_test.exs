defmodule Vxpipe.Providers.ElevenLabs.ScribeProfileSessionTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsProjection, SettingsSupervisor}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Channel, DiagnosticSubscription, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
  @projection __MODULE__.Projection

  setup do
    parent = self()

    store =
      start_supervised!(
        {Agent,
         fn -> %{enabled: false, revision: 1, now: System.monotonic_time(:millisecond)} end}
      )

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: @projection,
       reader: __MODULE__.Reader,
       send_after: fn _, _, _ -> make_ref() end,
       clock: fn -> Agent.get(store, & &1.now) end,
       loader: fn ->
         value = Agent.get(store, & &1)
         send(parent, {:settings_loaded, value.revision})
         {:ok, Map.take(value, [:enabled, :revision])}
       end}
    )

    loaded(1)
    %{store: store}
  end

  for wrapped <- [false, true] do
    test "profile query after enabling capture preserves existing #{if wrapped, do: "wrapped", else: "direct"} speech",
         %{store: store} do
      {session, wire} =
        start_session(unquote(wrapped), %{
          "model_id" => "scribe_v2_realtime",
          "commit_strategy" => "vad"
        })

      assert {:error, :unavailable} = SettingsProjection.grant(@projection)
      assert :ok = Session.push_audio(session, <<1, 0>>)
      assert_receive {:scribe_audio, ^wire, <<1, 0>>}
      enable(store)
      {:ok, handoff} = CaptureHandoff.new(self(), projection: @projection)
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
    test "manual #{if wrapped, do: "wrapped", else: "direct"} query is explicitly unsupported", %{
      store: store
    } do
      {session, wire} = start_session(unquote(wrapped), %{"commit_strategy" => "manual"}, :manual)
      enable(store)
      {:ok, handoff} = CaptureHandoff.new(self(), projection: @projection)
      assert :ok = DiagnosticSubscription.request_profile(session, handoff)
      canonical = session.generation
      assert {:provider_profile, ^canonical, _provider, :unsupported} = packet(handoff)
      assert :ok = Session.push_audio(session, :binary.copy(<<7, 0>>, 2_048))
      assert_receive {:scribe_audio, ^wire, _}, 1_000
    end

    test "profile query preserves an existing #{if wrapped, do: "wrapped", else: "direct"} observation",
         %{store: store} do
      {session, wire} =
        start_session(unquote(wrapped), %{
          "model_id" => "scribe_v2_realtime",
          "commit_strategy" => "vad"
        })

      enable(store)
      {:ok, capture} = CaptureHandoff.new(self(), projection: @projection)
      assert :ok = Channel.observe(session, capture)
      assert_receive {:scribe_observing, ^wire, token}
      assert token == capture.token
      {:ok, query} = CaptureHandoff.new(self(), projection: @projection)
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

  defp enable(store) do
    Agent.update(store, &%{&1 | enabled: true, revision: 2, now: &1.now + 1_000})
    :ok = SettingsProjection.invalidate(@projection)
    _ = :sys.get_state(@projection)
    poll = :sys.get_state(@projection).poll
    send(@projection, {:poll, poll})
    loaded(2)
  end

  defp loaded(revision) do
    assert_receive {:settings_loaded, ^revision}, 1_000
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(@projection)
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
