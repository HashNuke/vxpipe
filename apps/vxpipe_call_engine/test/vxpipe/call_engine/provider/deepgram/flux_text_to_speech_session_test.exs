defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech.Session, as: FluxSession
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.{SpeechSessionOwner, TestTextToSpeechTransport}

  test "a failed Flush retains submission evidence for the accepted Speak" do
    {session, wire} = start_session(fail_after_controls: 1)
    provider = Session.provider(session)
    monitor = Process.monitor(provider)

    assert {:ok, %{ref: request}} = Session.speak(session, "Hello")
    assert_control(wire, %{"type" => "Speak", "text" => "Hello"})

    assert_receive {:vxpipe_speech,
                    %Event{
                      session: ^session,
                      request_ref: ^request,
                      kind: :input_submitted,
                      provenance: :provider_reported
                    }},
                   500

    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 1_000
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
  end

  test "zero-played cancellation releases fenced wire audio and isolates a replacement" do
    {session, wire} = start_session()
    request = speak(session, wire, "first")
    wire_reference = TestTextToSpeechTransport.deliver_audio_with_result(wire, <<1, 0, 2, 0>>)

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, request_ref: ^request} = audio},
                   500

    assert :ok = Session.validate_audio(session, audio)
    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, playback} = Session.cancel(session, ticket, 0)
    assert playback.request_played_ms == 0
    assert playback.session_played_ms == 0
    assert_receive {:test_tts_audio_result, ^wire_reference, :ok}, 500
    refute_control("Interrupt")

    late_reference =
      TestTextToSpeechTransport.deliver_audio_with_result(wire, <<3, 0, 4, 0>>)

    assert_receive {:test_tts_audio_result, ^late_reference, :ok}, 500
    refute_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request}}, 20

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => "dg_sp_first"})
    )

    assert %Event{
             kind: :cancelled,
             request_ref: ^request,
             provider_request_id: "dg_sp_first"
           } = next_event(session)

    replacement = speak(session, wire, "replacement")
    refute replacement == request
    assert :ok = Session.close(session)
  end

  test "interrupts use cumulative locally confirmed playback across requests" do
    {session, wire} = start_session()
    first = speak(session, wire, "first")
    accept_audio(session, wire, first, :binary.copy(<<1, 0>>, 1_600))
    assert {:ok, first_ticket} = Session.fence_output(session, first)
    assert {:ok, first_playback} = Session.cancel(session, first_ticket, 40)
    assert first_playback.session_played_ms == 40
    assert_interrupt(wire, 40)
    interrupt(session, wire, first, "dg_sp_first", 40)

    second = speak(session, wire, "second")
    accept_audio(session, wire, second, :binary.copy(<<2, 0>>, 1_600))
    assert {:ok, second_ticket} = Session.fence_output(session, second)
    assert {:ok, second_playback} = Session.cancel(session, second_ticket, 20)
    assert second_playback.session_played_ms == 60
    assert_interrupt(wire, 60)
    interrupt(session, wire, second, "dg_sp_second", 60)
  end

  test "provider completion between fence and cancel settles as one cancellation" do
    {session, wire} = start_session()
    request = speak(session, wire, "already finishing")
    assert {:ok, ticket} = Session.fence_output(session, request)

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => "dg_sp_fence_race"})
    )

    assert %Event{
             kind: :cancelled,
             request_ref: ^request,
             provider_request_id: "dg_sp_fence_race"
           } = next_event(session)

    assert {:ok, playback} = Session.cancel(session, ticket, 0)
    assert playback.request_ref == request
    assert playback.request_played_ms == 0
    assert {:ok, ^playback} = Session.cancel(session, ticket, 0)
    assert {:ok, ^ticket} = Session.fence_output(session, request)
    refute_control("Interrupt")

    replacement = speak(session, wire, "replacement")
    refute replacement == request
    assert {:ok, ^playback} = Session.cancel(session, ticket, 0)
    assert :ok = Session.close(session)
  end

  test "audio arriving between fence and cancel is discarded without retiring the session" do
    {session, wire} = start_session()
    request = speak(session, wire, "fence audio race")
    assert {:ok, ticket} = Session.fence_output(session, request)

    wire_reference =
      TestTextToSpeechTransport.deliver_audio_with_result(wire, <<1, 0, 2, 0>>)

    assert_receive {:test_tts_audio_result, ^wire_reference, :ok}, 500
    assert {:ok, playback} = Session.cancel(session, ticket, 0)
    assert playback.request_ref == request

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => "dg_sp_fence_audio"})
    )

    assert %Event{
             kind: :cancelled,
             request_ref: ^request,
             provider_request_id: "dg_sp_fence_audio"
           } = next_event(session)

    replacement = speak(session, wire, "replacement")
    refute replacement == request
    assert :ok = Session.close(session)
  end

  test "a provider disconnect retires only its allocation while a sibling keeps synthesizing" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    scope = CapabilityTree.scope(tree)
    {session, wire} = start_session_in(scope, [])

    assert {:ok, sibling, :starting} =
             Session.start(scope,
               provider: MorseSession,
               options: [sample_rate: 8_000, unit_duration_ms: 20],
               private: [emit_interval_ms: 0]
             )

    assert %Event{kind: :ready} = next_event(sibling)
    session_tree = Session.tree(session)
    monitor = Process.monitor(session_tree)
    TestTextToSpeechTransport.disconnect(wire, :synthetic_disconnect)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session_tree, _reason}, 1_000
    refute_receive {:test_tts_transport_started, _replacement, _connection}, 20

    assert {:ok, %{ref: request}} = Session.speak(sibling, "E")
    assert byte_size(drain_audio(sibling, request, [])) == 4_800
  end

  test "a provider terminal failure retires the request without a semantic success" do
    {session, wire} = start_session()
    request = speak(session, wire, "fail")
    session_tree = Session.tree(session)
    monitor = Process.monitor(session_tree)

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "Error", "code" => "SYNTHETIC_FAILURE"})
    )

    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^session_tree, _reason}, 1_000

    refute_receive {:vxpipe_speech, %Event{request_ref: ^request, kind: :completed}}, 20
    refute_receive {:vxpipe_speech, %Event{request_ref: ^request, kind: :cancelled}}, 20
  end

  test "a nonfatal provider warning leaves the active request usable" do
    {session, wire} = start_session()
    request = speak(session, wire, "warn then continue")

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "Warning", "code" => "SYNTHESIS_RETRYING"})
    )

    accept_audio(session, wire, request, <<1, 0, 2, 0>>)

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => "dg_sp_warned"})
    )

    assert %Event{
             kind: :completed,
             request_ref: ^request,
             provider_request_id: "dg_sp_warned"
           } = next_event(session)
  end

  test "long provider output stays one credited chunk at a time" do
    {session, wire} = start_session()
    request = speak(session, wire, "long output")
    chunk = :binary.copy(<<1, 0>>, 2_048)

    for _index <- 1..40 do
      accept_audio(session, wire, request, chunk)
    end

    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => "dg_sp_long"})
    )

    assert %Event{
             kind: :completed,
             request_ref: ^request,
             provider_request_id: "dg_sp_long"
           } = next_event(session)
  end

  test "owner loss tears down the allocation and its private wire" do
    owner =
      start_supervised!(Supervisor.child_spec({SpeechSessionOwner, self()}, restart: :temporary))

    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             FluxTextToSpeech.new(
               api_key: "synthetic-owner-loss-secret",
               model: "flux-haley-en",
               encoding: :linear16,
               sample_rate: 16_000
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               owner: owner,
               provider: FluxSession,
               options: [
                 model: config.model,
                 encoding: config.encoding,
                 sample_rate: config.sample_rate
               ],
               private: [
                 config: config,
                 wire_module: TestTextToSpeechTransport,
                 wire_options: [observer: self(), ready_on_start: true]
               ]
             )

    assert_receive {:test_tts_transport_started, wire, _connection}, 1_000

    assert_receive {:speech_owner, ^owner,
                    {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}},
                   1_000

    assert :ok = SpeechSessionOwner.run(owner, fn _ -> Session.ack(session, ready) end)
    session_tree = Session.tree(session)
    tree_monitor = Process.monitor(session_tree)
    wire_monitor = Process.monitor(wire)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^tree_monitor, :process, ^session_tree, _reason}, 1_000
    assert_receive {:DOWN, ^wire_monitor, :process, ^wire, _reason}, 1_000
  end

  test "public configuration excludes credentials and rejects wire or transport settings" do
    assert {:ok, descriptor} =
             FluxSession.configure(
               model: "flux-haley-en",
               encoding: :linear16,
               sample_rate: 16_000
             )

    assert descriptor.settings == %{
             model: "flux-haley-en",
             encoding: :linear16,
             sample_rate: 16_000
           }

    assert descriptor.readiness == :provider_acknowledged
    assert descriptor.usage_identity.provenance == :provider_reported

    for invalid <- [
          [api_key: "forbidden"],
          [wire_module: TestTextToSpeechTransport],
          [wire_options: []],
          [transport: {TestTextToSpeechTransport, []}],
          [transport_options: []]
        ] do
      assert {:error, :invalid_configuration} = FluxSession.configure(invalid)
    end
  end

  test "provider state and status omit credentials and submitted text" do
    secret_text = "do-not-retain-submitted-text"
    {session, wire} = start_session()
    _request = speak(session, wire, secret_text)
    provider = Session.provider(session)

    for status <- [:sys.get_state(provider), :sys.get_status(provider)] do
      inspected = inspect(status, limit: :infinity)
      refute inspected =~ "synthetic-tts-session-secret"
      refute inspected =~ secret_text
    end

    assert :ok = Session.close(session)
  end

  defp start_session(wire_options \\ []) do
    tree = start_supervised!({CapabilityTree, owner: self()})
    start_session_in(CapabilityTree.scope(tree), wire_options)
  end

  defp start_session_in(scope, wire_options) do
    assert {:ok, config} =
             FluxTextToSpeech.new(
               api_key: "synthetic-tts-session-secret",
               model: "flux-haley-en",
               encoding: :linear16,
               sample_rate: 16_000
             )

    wire_options =
      Keyword.merge([observer: self(), ready_on_start: true], wire_options)

    assert {:ok, session, :starting} =
             Session.start(scope,
               provider: FluxSession,
               options: [
                 model: config.model,
                 encoding: config.encoding,
                 sample_rate: config.sample_rate
               ],
               private: [
                 config: config,
                 wire_module: TestTextToSpeechTransport,
                 wire_options: wire_options
               ]
             )

    assert_receive {:test_tts_transport_started, wire, connection}, 1_000
    assert connection.headers == [{"Authorization", "Token synthetic-tts-session-secret"}]
    assert %Event{kind: :ready, readiness: :provider_acknowledged} = next_event(session)
    {session, wire}
  end

  defp drain_audio(session, request, chunks) do
    receive do
      {:vxpipe_speech_audio,
       %Audio{session: ^session, request_ref: ^request, payload: payload} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        drain_audio(session, request, [payload | chunks])

      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request} = event} ->
        assert :ok = Session.ack(session, event)

        if event.kind == :completed,
          do: chunks |> Enum.reverse() |> IO.iodata_to_binary(),
          else: drain_audio(session, request, chunks)
    after
      1_000 -> flunk("sibling synthesis did not complete")
    end
  end

  defp speak(session, wire, text) do
    assert {:ok, %{ref: request}} = Session.speak(session, text)
    assert_control(wire, %{"type" => "Speak", "text" => text})
    assert_control(wire, %{"type" => "Flush"})
    assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)
    request
  end

  defp accept_audio(session, wire, request, payload) do
    wire_reference = TestTextToSpeechTransport.deliver_audio_with_result(wire, payload)

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, request_ref: ^request, payload: ^payload} = audio},
                   500

    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_tts_audio_result, ^wire_reference, :ok}, 500
  end

  defp interrupt(session, wire, request, speech_id, played_ms) do
    TestTextToSpeechTransport.deliver_control(
      wire,
      JSON.encode!(%{
        "type" => "SpeechInterrupted",
        "audio_played_ms" => played_ms,
        "text_spoken" => "heard",
        "text_remaining" => "remaining",
        "metadata" => %{"speech_id" => speech_id}
      })
    )

    assert %Event{
             kind: :cancelled,
             request_ref: ^request,
             provider_request_id: ^speech_id
           } = next_event(session)
  end

  defp assert_interrupt(wire, expected) do
    assert_receive {:test_tts_control, ^wire, payload}, 500

    assert JSON.decode!(payload) == %{
             "type" => "Interrupt",
             "playback_offset" => %{"type" => "time_ms", "value" => expected}
           }
  end

  defp assert_control(wire, expected) do
    assert_receive {:test_tts_control, ^wire, payload}, 500
    assert JSON.decode!(payload) == expected
  end

  defp refute_control(type) do
    receive do
      {:test_tts_control, _wire, payload} ->
        refute JSON.decode!(payload)["type"] == type
    after
      20 -> :ok
    end
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
