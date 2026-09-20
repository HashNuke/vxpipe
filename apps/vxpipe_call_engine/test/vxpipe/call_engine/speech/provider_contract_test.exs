defmodule Vxpipe.CallEngine.Speech.ProviderContractTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.SpeechToText.State, as: SpeechToTextState
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux.Session, as: DeepgramSTT
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech.Session, as: DeepgramTTS
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSTT
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseTTS
  alias Vxpipe.CallEngine.Speech.{Event, Session}
  alias Vxpipe.CallEngine.SpeechGuideTTSProvider, as: GuideTTS
  alias Vxpipe.CallEngine.SpeechProviderContract, as: Contract
  alias Vxpipe.CallEngine.SpeechRequestTTSProfile, as: RequestTTS
  alias Vxpipe.CallEngine.SpeechSegmentedSTTProfile, as: SegmentedSTT
  alias Vxpipe.CallEngine.SpeechSessionOwner
  alias Vxpipe.CallEngine.{TestSpeechToTextTransport, TestTextToSpeechTransport}

  test "native and structural providers publish valid closed descriptors" do
    assert :ok = Contract.assert_descriptor(MorseSTT, [], :stt)
    assert :ok = Contract.assert_descriptor(MorseTTS, [], :tts)

    assert :ok =
             Contract.assert_descriptor(
               DeepgramSTT,
               [encoding: :opus, sample_rate: 48_000],
               :stt
             )

    assert :ok = Contract.assert_descriptor(DeepgramTTS, [], :tts)
    assert :ok = Contract.assert_descriptor(SegmentedSTT, [], :stt)
    assert :ok = Contract.assert_descriptor(RequestTTS, [], :tts)
    assert :ok = Contract.assert_descriptor(GuideTTS, [], :tts)
  end

  test "the guide's minimal provider runs through the public contract" do
    session =
      Contract.start_profile!(GuideTTS,
        private: [credential: "test-credential", observer: self()]
      )

    assert_receive {:speech_guide_client_initialized, provider}
    assert provider == Session.provider(session)
    assert {:ok, request} = Session.speak(session, "guide")
    assert Contract.drain_tts!(session, request.ref) == <<0, 0>>
  end

  test "native Morse STT and TTS run through the shared lifecycle checks" do
    options = [sample_rate: 8_000, unit_duration_ms: 20]
    assert {:ok, config} = Config.new(options)
    assert {:ok, input} = Encoder.encode(config, "E")

    stt = Contract.start_profile!(MorseSTT, options: options)
    assert :ok = Session.push_audio(stt, input)
    [started, transcript, ended] = Contract.ack_events!(stt, 3)

    assert {started.kind, transcript.kind, transcript.text, ended.kind, ended.text} ==
             {:speech_started, :transcript, "E", :turn_ended, "E"}

    tts = Contract.start_profile!(MorseTTS, options: options, private: [emit_interval_ms: 0])
    assert {:ok, request} = Session.speak(tts, "E")
    assert Contract.drain_tts!(tts, request.ref) == input
  end

  test "native hosted STT and TTS pass shared readiness, media and terminal checks" do
    assert {:ok, stt_config} =
             Flux.new(
               api_key: "test-stt-credential",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    stt =
      Contract.start_session!(Contract.start_scope!(), DeepgramSTT,
        options: [
          model: stt_config.model,
          encoding: stt_config.encoding,
          sample_rate: stt_config.sample_rate
        ],
        private: [
          config: stt_config,
          wire_module: TestSpeechToTextTransport,
          wire_options: [observer: self(), ready_on_start: true]
        ]
      )

    assert_receive {:test_stt_transport_started, stt_wire, _connection}
    Contract.ack_ready!(stt)
    assert :ok = Session.push_audio(stt, <<1, 2, 3>>)
    assert_receive {:test_stt_audio, ^stt_wire, <<1, 2, 3>>}
    TestSpeechToTextTransport.deliver(stt_wire, deepgram_turn("StartOfTurn", 1, "hello"))
    [started, transcript] = Contract.ack_events!(stt, 2)

    assert {started.kind, transcript.kind, transcript.text} ==
             {:speech_started, :transcript, "hello"}

    TestSpeechToTextTransport.deliver(stt_wire, deepgram_turn("EndOfTurn", 2, "hello"))
    assert Contract.ack_event!(stt, :turn_ended).text == "hello"

    assert {:ok, tts_config} =
             FluxTextToSpeech.new(
               api_key: "test-tts-credential",
               model: "flux-haley-en",
               encoding: :linear16,
               sample_rate: 16_000
             )

    tts =
      Contract.start_session!(Contract.start_scope!(), DeepgramTTS,
        options: [
          model: tts_config.model,
          encoding: tts_config.encoding,
          sample_rate: tts_config.sample_rate
        ],
        private: [
          config: tts_config,
          wire_module: TestTextToSpeechTransport,
          wire_options: [observer: self(), ready_on_start: true]
        ]
      )

    assert_receive {:test_tts_transport_started, tts_wire, _connection}
    Contract.ack_ready!(tts)
    assert {:ok, request} = Session.speak(tts, "hello")
    Contract.ack_event!(tts, :input_submitted)
    assert_receive {:test_tts_control, ^tts_wire, _speak}
    assert_receive {:test_tts_control, ^tts_wire, _flush}

    wire_reference =
      TestTextToSpeechTransport.deliver_audio_with_result(tts_wire, <<1, 0, 2, 0>>)

    audio = Contract.next_audio!(tts, request.ref, <<1, 0, 2, 0>>)
    refute_receive {:test_tts_audio_result, ^wire_reference, _result}, 50
    assert :ok = Contract.ack_received_audio!(tts, audio)
    assert_receive {:test_tts_audio_result, ^wire_reference, :ok}

    TestTextToSpeechTransport.deliver_control(
      tts_wire,
      JSON.encode!(%{"type" => "SpeechMetadata", "speech_id" => "contract-terminal"})
    )

    completed = Contract.ack_event!(tts, :completed)
    assert completed.request_ref == request.ref
    assert completed.provider_request_id == "contract-terminal"
  end

  test "a starting handle is not readiness and a held provider does not block its sibling" do
    scope = Contract.start_scope!()

    held =
      Contract.start_session!(scope, RequestTTS,
        private: [
          credential: "test-credential",
          observer: self(),
          hold_ready?: true,
          responses: [{:streamed, [<<1, 0>>]}]
        ]
      )

    assert_receive {:speech_profile_bound, held_provider}
    assert {:error, :not_ready} = Session.speak(held, "held")

    sibling =
      Contract.start_session!(scope, RequestTTS,
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [{:streamed, [<<2, 0>>]}]
        ]
      )

    Contract.ack_ready!(sibling)
    assert {:ok, request} = Session.speak(sibling, "sibling")
    assert Contract.drain_tts!(sibling, request.ref) == <<2, 0>>

    send(held_provider, :release_ready)
    Contract.ack_ready!(held)
  end

  test "startup deadline and queued cancellation cannot create a late provider" do
    scope = Contract.start_scope!()

    expiring =
      Contract.start_session!(scope, RequestTTS,
        start_timeout: 40,
        private: [
          credential: "test-credential",
          observer: self(),
          hold_ready?: true,
          responses: []
        ]
      )

    assert_receive {:speech_profile_bound, expiring_provider}
    monitor = Process.monitor(expiring_provider)
    assert_receive {:vxpipe_speech_closed, ^expiring, reason}, 500
    assert reason in [:startup_timeout, :initialization_failed]
    assert_receive {:DOWN, ^monitor, :process, ^expiring_provider, _reason}, 500

    initialization_hook = fn
      {:speech_profile_bound, provider} -> {:ok, provider}
      _message -> :ignore
    end

    assert :ok =
             Contract.assert_cancelled_start_never_initializes!(
               Contract.start_scope!(),
               RequestTTS,
               [
                 private: [
                   credential: "test-credential",
                   observer: self(),
                   responses: []
                 ]
               ],
               initialization_hook
             )
  end

  test "request providers adapt streamed and bounded whole responses with exact audio credit" do
    streamed =
      Contract.start_profile!(RequestTTS,
        options: [delivery: :streamed, chunk_bytes: 4],
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [{:streamed, [<<1, 0, 2, 0>>, <<3, 0>>]}]
        ]
      )

    assert {:ok, streamed_request} = Session.speak(streamed, "stream this")
    assert Contract.drain_tts!(streamed, streamed_request.ref) == <<1, 0, 2, 0, 3, 0>>
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}

    whole =
      Contract.start_profile!(RequestTTS,
        options: [delivery: :whole, chunk_bytes: 4, maximum_response_bytes: 16],
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [{:whole, <<4, 0, 5, 0, 6, 0, 7, 0, 8, 0>>}]
        ]
      )

    assert {:ok, whole_request} = Session.speak(whole, "return whole")
    assert Contract.drain_tts!(whole, whole_request.ref) == <<4, 0, 5, 0, 6, 0, 7, 0, 8, 0>>
  end

  test "whole task results are bounded and PCM aligned after submission" do
    for invalid_audio <- [
          <<1, 0, 2, 0, 3, 0, 4, 0, 5, 0>>,
          <<1, 0, 2>>
        ] do
      session =
        Contract.start_profile!(RequestTTS,
          options: [delivery: :whole, chunk_bytes: 4, maximum_response_bytes: 8],
          private: [
            credential: "test-credential",
            observer: self(),
            responses: [{:held, invalid_audio}]
          ]
        )

      tree = Session.tree(session)
      monitor = Process.monitor(tree)
      assert {:ok, request} = Session.speak(session, "invalid worker result")
      request_ref = request.ref

      assert_receive {:speech_profile_task, token, _task_ref, worker,
                      %{request_ref: ^request_ref}}

      Contract.ack_event!(session, :input_submitted)
      send(worker, {:speech_profile_release, token})
      assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 500
      assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}, 500
    end
  end

  test "streamed and whole request workers stop at one uncredited chunk" do
    for {delivery, response} <- [
          {:streamed, {:streamed, [<<1, 0>>, <<2, 0>>]}},
          {:whole, {:whole, <<1, 0, 2, 0>>}}
        ] do
      session =
        Contract.start_profile!(RequestTTS,
          options: [delivery: delivery, chunk_bytes: 2],
          private: [
            credential: "test-credential",
            observer: self(),
            responses: [response]
          ]
        )

      assert {:ok, request} = Session.speak(session, "credit")
      Contract.ack_event!(session, :input_submitted)
      first = Contract.next_audio!(session, request.ref, <<1, 0>>)
      refute_receive {:vxpipe_speech_audio, %{session: ^session}}, 50
      refute_receive {:vxpipe_speech, %Event{session: ^session, kind: :completed}}, 50
      assert :ok = Contract.ack_received_audio!(session, first)
      Contract.ack_audio!(session, request.ref, <<2, 0>>)
      Contract.ack_event!(session, :completed)
    end
  end

  test "context cancellation kills the owned worker and stale completion cannot revive output" do
    session =
      Contract.start_profile!(RequestTTS,
        options: [delivery: :whole, chunk_bytes: 4],
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [
            {:held, <<9, 0>>},
            {:whole, <<10, 0, 11, 0>>}
          ]
        ]
      )

    provider = Session.provider(session)
    assert {:ok, first} = Session.speak(session, "cancel me")
    Contract.ack_event!(session, :input_submitted)

    assert_receive {:speech_profile_task, token, task_ref, worker, context}
    assert context.request_ref == first.ref
    worker_monitor = Process.monitor(worker)

    assert {:ok, ticket} = Session.fence_output(session, first)
    assert {:ok, playback} = Session.cancel(session, ticket, 0)
    assert playback.request_ref == first.ref
    assert_receive {:speech_profile_cancelled, ^token, ^context}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _reason}, 500
    Contract.ack_event!(session, :cancelled)

    assert {:ok, replacement} = Session.speak(session, "replacement")
    Contract.ack_event!(session, :input_submitted)
    RequestTTS.deliver_late(provider, task_ref, token, <<99, 0>>)
    assert Contract.drain_tts!(session, replacement.ref) == <<10, 0, 11, 0>>
  end

  test "owner death tears down a request worker with its allocation tree" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    scope = Contract.start_scope!(owner)

    session =
      Contract.start_session!(scope, RequestTTS,
        owner: owner,
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [{:held, <<12, 0>>}]
        ]
      )

    Contract.ack_ready!(session)
    assert {:ok, _request} = Session.speak(session, "owned")
    Contract.ack_event!(session, :input_submitted)
    assert_receive {:speech_profile_task, _token, _task_ref, worker, _context}

    worker_monitor = Process.monitor(worker)
    tree = Session.tree(session)
    tree_monitor = Process.monitor(tree)
    GenServer.stop(owner)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _reason}, 500
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _reason}, 500
  end

  test "batch boundaries never stand in for request completion" do
    session =
      Contract.start_profile!(RequestTTS,
        options: [delivery: :batched, chunk_bytes: 4],
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [{:batched, [[<<1, 0>>], [<<2, 0>>]], :gate_first}]
        ]
      )

    provider = Session.provider(session)
    assert {:ok, request} = Session.speak(session, "two batches")
    Contract.ack_event!(session, :input_submitted)

    Contract.ack_audio!(session, request.ref, <<1, 0>>)
    assert_receive {:speech_profile_batch_done, token, 1, context}
    assert context.request_ref == request.ref
    refute_receive {:vxpipe_speech, %Event{session: ^session, kind: :completed}}, 50

    assert :ok = RequestTTS.continue_batch(provider, token, 1)
    Contract.ack_audio!(session, request.ref, <<2, 0>>)
    assert_receive {:speech_profile_batch_done, ^token, 2, ^context}
    Contract.ack_event!(session, :completed)

    coalesced =
      Contract.start_profile!(RequestTTS,
        options: [delivery: :batched, chunk_bytes: 4],
        private: [
          credential: "test-credential",
          observer: self(),
          responses: [{:coalesced, [<<3, 0>>], 2}]
        ]
      )

    coalesced_provider = Session.provider(coalesced)
    assert {:ok, coalesced_request} = Session.speak(coalesced, "coalesced flushes")
    Contract.ack_event!(coalesced, :input_submitted)
    Contract.ack_audio!(coalesced, coalesced_request.ref, <<3, 0>>)

    assert_receive {:speech_profile_batches_coalesced, coalesced_token, 2, 1, coalesced_context}

    assert coalesced_context.request_ref == coalesced_request.ref
    refute_receive {:vxpipe_speech, %Event{session: ^coalesced, kind: :completed}}, 50

    assert :ok =
             RequestTTS.continue_batch(coalesced_provider, coalesced_token, :coalesced)

    Contract.ack_event!(coalesced, :completed)
  end

  test "segmented STT keeps revisions, commits, eager end, resume and actual end distinct" do
    session =
      Contract.start_profile!(SegmentedSTT,
        private: [credential: "test-credential", observer: self()]
      )

    for command <- 1..8 do
      assert :ok = Session.push_audio(session, <<command>>)
    end

    events = Contract.ack_events!(session, 8)

    assert Enum.map(events, & &1.kind) == [
             :speech_started,
             :transcript,
             :transcript,
             :transcript,
             :transcript,
             :eager_turn_ended,
             :turn_resumed,
             :turn_ended
           ]

    assert Enum.map(Enum.slice(events, 1, 4), & &1.text) == [
             "hel",
             "hello",
             "hello ",
             "hello worl"
           ]

    assert_receive {:speech_profile_segment_committed, "hello "}
    assert Enum.at(events, 5).text == "hello world"
    assert Enum.at(events, 7).text == "hello world!"
    assert Enum.uniq(Enum.map(events, & &1.turn_ref)) |> length() == 1
    assert Enum.all?(events, &is_nil(&1.provider_request_id))

    sequences = Enum.map(events, & &1.sequence)
    assert sequences == Enum.to_list(hd(sequences)..List.last(sequences))
  end

  test "conversational admission rejects an STT descriptor with no end-of-turn authority" do
    scope = Contract.start_scope!()

    for provider_options <- [
          [endpointing: :none],
          [endpointing: :provider_semantic, speech_start?: false]
        ] do
      assert {:error, :provider_start_failed, SegmentedSTT} =
               SpeechToTextState.new(
                 owner: self(),
                 tenant_id: "tenant-contract",
                 room_id: "room-contract",
                 incarnation_id: "incarnation-contract",
                 participant_id: "participant-contract",
                 connection_id: "connection-contract",
                 speech_scope: scope,
                 provider: {SegmentedSTT, provider_options},
                 provider_private: [credential: "test-credential", observer: self()]
               )
    end

    refute_receive {:speech_profile_stt_started, _provider}
  end

  defp deepgram_turn(event, sequence, transcript) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "contract-stt",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 1.0,
      "trigger" => "model"
    })
  end
end
