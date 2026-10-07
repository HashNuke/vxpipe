defmodule Vxpipe.Gateway.PhoneHandoffAssertions do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.TestSpeechToTextTransport
  alias Vxpipe.Gateway.TestTelephonySocket
  alias Vxpipe.Gateway.Telephony.MediaSupervisor
  alias Vxpipe.Providers.Twilio.PCMU.Codec

  def scenario_options(mode) do
    base = [
      support_speech_to_text?: true,
      recording: [
        enabled: true,
        targets: [:full_mix, :individual_tracks],
        writer: {CallEngine.TestRecordingWriter, observer: self()},
        maximum_pull_frames: 20
      ]
    ]

    case mode do
      :defaults ->
        Keyword.put(base, :wait_sounds, %{call_setup: nil})

      :silent_all ->
        Keyword.put(base, :wait_sounds, nil)

      :custom_url ->
        cache =
          start_supervised!(
            {CallEngine.OpeningAudio.AssetCache, maximum_entries: 8, maximum_bytes: 8_388_608}
          )

        url = "https://media.example.com/phone-wait.wav"

        configured = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

        audio_settings =
          Keyword.merge(Keyword.fetch!(configured, :opening_audio),
            cache: cache,
            fetcher:
              {CallEngine.TestOpeningAudioFetcher,
               [
                 observer: self(),
                 response:
                   {:ok,
                    %CallEngine.OpeningAudio.Download{
                      body: wave(250),
                      content_type: "audio/wav"
                    }}
               ]}
          )

        Application.put_env(
          :vxpipe_call_engine,
          CallEngine.Application,
          Keyword.put(configured, :opening_audio, audio_settings)
        )

        Keyword.put(base, :wait_sounds, %{
          call_setup: nil,
          transfer_to_human: url,
          transfer_joining: url
        })
    end
  end

  def gate(provider, plan, {mode, loss}, incoming, outgoing, caller_stt, support_stt, leg_ids) do
    {incoming_id, outgoing_id} = leg_ids

    if mode == :custom_url do
      assert_receive {:test_opening_audio_fetch, "https://media.example.com/phone-wait.wav", _},
                     1_000
    end

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    assert {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(authority)
    assert {:ok, caller} = MediaSupervisor.snapshot(incoming_id)
    assert {:ok, support} = MediaSupervisor.snapshot(outgoing_id)
    assert support.attachment.admission == :transfer_preparation
    caller_id = Map.fetch!(plan.participants, "caller").participant_id
    caller_monitor = Process.monitor(caller_stt)
    support_monitor = Process.monitor(support_stt)
    failure_token = observe_failure(incoming_id)
    output_decoder = decoder(provider)

    for socket <- [incoming, outgoing] do
      drain_output(socket)
      assert_wait(socket, provider, mode)
    end

    assert_private_recordings(caller_id, System.monotonic_time(:millisecond))
    send_tone(outgoing, provider, support.stream_id, 1_500, 200)
    refute_receive {:test_stt_audio, ^support_stt, _private_audio}, 100
    refute_receive {:test_stt_audio, ^caller_stt, _private_audio}, 100
    assert_private_recordings(caller_id, System.monotonic_time(:millisecond) + 100)

    assert {:ok, %{attachment: %{admission: :transfer_preparation}}} =
             MediaSupervisor.snapshot(outgoing_id)

    cue_mark =
      if loss == :destination do
        assert :ok = ExUnit.Callbacks.stop_supervised(:outgoing_socket)
        nil
      else
        assert :ok = TestTelephonySocket.automatic_marks(outgoing, false)
        drain_output(incoming)
        drain_output(outgoing)

        TestSpeechToTextTransport.deliver(
          support_stt,
          ~s({"type":"Connected","request_id":"phone-support-ready","sequence_id":0})
        )

        {cue_mark, old_marks} =
          cue_mark(
            outgoing,
            output_decoder,
            [],
            false,
            System.monotonic_time(:millisecond) + 3_000
          )

        assert old_marks != []

        for old <- old_marks do
          assert old != cue_mark
          assert :ok = TestTelephonySocket.acknowledge_mark(outgoing, old)
        end

        refute_receive {:DOWN, ^caller_monitor, :process, ^caller_stt, _}, 50

        assert {:ok, %{attachment: %{admission: :transfer_preparation}}} =
                 MediaSupervisor.snapshot(outgoing_id)

        assert_private_recordings(caller_id, System.monotonic_time(:millisecond))
        assert {:ok, current} = CallEngine.RoomAuthority.readiness_binding(authority)
        assert current.attempt == binding.attempt

        if loss == :cue do
          assert :ok = ExUnit.Callbacks.stop_supervised(:outgoing_socket)
        else
          assert :ok = TestTelephonySocket.acknowledge_mark(outgoing, cue_mark)
          assert :ok = TestTelephonySocket.automatic_marks(outgoing, true)
        end

        cue_mark
      end

    %{
      provider: provider,
      plan: plan,
      authority: authority,
      binding: binding,
      caller: caller,
      support: support,
      caller_stt: caller_stt,
      support_stt: support_stt,
      incoming: incoming,
      outgoing: outgoing,
      incoming_id: incoming_id,
      outgoing_id: outgoing_id,
      mode: mode,
      decoder: output_decoder,
      cue_mark: cue_mark,
      loss: loss,
      failure_token: failure_token,
      support_monitor: support_monitor
    }
  end

  def conversation(proof) do
    assert {:ok, caller} = MediaSupervisor.snapshot(proof.incoming_id)
    assert {:ok, support} = MediaSupervisor.snapshot(proof.outgoing_id)
    assert support.attachment.admission == :main

    for {before, after_transfer} <- [{proof.caller, caller}, {proof.support, support}] do
      assert before.audio_output == after_transfer.audio_output
      assert before.room_audio_ingress == after_transfer.room_audio_ingress
      assert before.room_audio_egress == after_transfer.room_audio_egress
    end

    assert caller.attachment.media_ingress == proof.caller.attachment.media_ingress
    assert {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(proof.authority)
    assert binding.room == proof.binding.room
    assert binding.attempt == nil
    refute_receive {:test_stt_transport_started, _replacement, _}, 0
    assert :ok = TestTelephonySocket.acknowledge_mark(proof.outgoing, proof.cue_mark)

    send_tone(proof.incoming, proof.provider, caller.stream_id, 500, 300)

    await_conversation(
      proof.outgoing,
      proof.decoder,
      500,
      proof.mode,
      :cue,
      System.monotonic_time(:millisecond) + 2_000
    )

    caller_stt = proof.caller_stt
    support_stt = proof.support_stt
    assert_receive {:test_stt_audio, ^caller_stt, _audio}, 2_000
    send_tone(proof.outgoing, proof.provider, support.stream_id, 1_500, 300)

    await_conversation(
      proof.incoming,
      decoder(proof.provider),
      1_500,
      proof.mode,
      :waiting,
      System.monotonic_time(:millisecond) + 2_000
    )

    assert_receive {:test_stt_audio, ^support_stt, _audio}, 2_000
    assert_receive {:test_recording_chunk, _, chunk}, 2_000
    assert byte_size(chunk.payload) > 0
    assert_transcripts(proof)
    refute_receive {:test_opening_audio_fetch, _url, _limits}, 0
  end

  def recovery(proof, source_tts) do
    token = proof.failure_token
    assert_receive {:phone_transfer_failed, ^token, %{name: "transfer"}}, 2_000
    monitor = proof.support_monitor
    support_stt = proof.support_stt
    assert_receive {:DOWN, ^monitor, :process, ^support_stt, _}, 2_000
    assert {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(proof.authority)
    assert binding.attempt == nil
    assert binding.room == proof.binding.room
    assert binding.participants == proof.binding.participants

    assert binding.connections ==
             Map.delete(proof.binding.connections, proof.support.connection_id)

    assert {:ok, caller} = MediaSupervisor.snapshot(proof.incoming_id)
    assert caller == proof.caller
    refute_receive {:test_stt_transport_started, _, _}, 0
    refute_receive {:test_tts_transport_started, _, _}, 0

    assert_receive {:test_agent_runtime_stream, provider, _}, 2_000
    send(provider, {:test_agent_runtime_delta, "We can continue.", self()})
    assert_receive {:test_agent_runtime_delta_result, :ok}, 2_000
    assert {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "We can continue.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    await_recovery_speech(source_tts, System.monotonic_time(:millisecond) + 5_000)

    CallEngine.TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"SpeechStarted","speech_id":"phone-recovery"})
    )

    CallEngine.TestTextToSpeechTransport.deliver_audio(source_tts, tone(1_250, 48_000, 4_800))

    CallEngine.TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"SpeechMetadata","speech_id":"phone-recovery"})
    )

    await_conversation(
      proof.incoming,
      decoder(proof.provider),
      1_250,
      proof.mode,
      :waiting,
      System.monotonic_time(:millisecond) + 2_000
    )

    send_tone(proof.incoming, proof.provider, caller.stream_id, 500, 300)

    request =
      if proof.provider == :telnyx, do: "request-telnyx-harness", else: "request-twilio-harness"

    deliver_transcript(proof.caller_stt, request, 3, "Continue helping me.")
    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 2_000
    assert Enum.any?(next_request.messages, &(&1.content == "Continue helping me."))
    assert {:ok, next_response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "Still here.")
    send(next_provider, {:test_agent_runtime_response, {:ok, next_response}})
    refute_receive {:test_opening_audio_fetch, _url, _limits}, 0
  end

  defp observe_failure(leg_id) do
    owner = self()
    token = make_ref()

    [{session, _}] =
      Registry.lookup(Vxpipe.Gateway.Media.Registry, {:telephony_media_session, leg_id})

    assert :ok =
             :sys.install(
               session,
               {token,
                fn state, event, _process ->
                  case event do
                    {:in, {:vxpipe_event, %CallEngine.Event.ToolCallFailed{} = failure}} ->
                      send(owner, {:phone_transfer_failed, token, failure})

                    _other ->
                      :ok
                  end

                  state
                end, nil}
             )

    token
  end

  def await_recovery_speech(voice, deadline), do: await_recovery_speech(voice, deadline, [])

  defp await_recovery_speech(voice, deadline, observed) do
    receive do
      {:test_tts_control, ^voice, control} ->
        case JSON.decode!(control) do
          %{"type" => "Speak", "text" => "We can continue."} ->
            :ok

          %{"type" => "Speak", "text" => earlier} when is_binary(earlier) ->
            # An earlier response or streaming fragment can reach TTS before
            # the handoff interrupts it. Complete the mock provider request.
            # Establish an output turn before completing an uncancelled request.
            # A fenced request discards these bytes through the same provider path.
            CallEngine.TestTextToSpeechTransport.deliver_control(
              voice,
              JSON.encode!(%{type: "SpeechStarted", speech_id: "transfer-acknowledgement"})
            )

            CallEngine.TestTextToSpeechTransport.deliver_audio(voice, tone(750, 48_000, 960))

            CallEngine.TestTextToSpeechTransport.deliver_control(
              voice,
              JSON.encode!(%{type: "SpeechMetadata", speech_id: "transfer-acknowledgement"})
            )

            facts =
              {:speak, byte_size(earlier), String.contains?(earlier, "We can continue."),
               String.trim(earlier) == "We can continue."}

            await_recovery_speech(voice, deadline, Enum.take([facts | observed], 32))

          other ->
            kind =
              case other do
                %{"type" => "Interrupt"} -> :interrupt
                %{"type" => "Flush"} -> :flush
                _other -> :other
              end

            await_recovery_speech(voice, deadline, Enum.take([kind | observed], 32))
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk(
          "missing source recovery speech; bounded controls #{inspect(Enum.reverse(observed))}"
        )
    end
  end

  defp assert_transcripts(proof) do
    owner = self()
    token = make_ref()
    discard_source_requests()

    for leg_id <- [proof.incoming_id, proof.outgoing_id] do
      [{session, _}] =
        Registry.lookup(
          Vxpipe.Gateway.Media.Registry,
          {:telephony_media_session, leg_id}
        )

      assert :ok =
               :sys.install(
                 session,
                 {token,
                  fn state, event, _process ->
                    case event do
                      {:in,
                       {:vxpipe_event, %CallEngine.Event.ParticipantTranscription{} = transcript}} ->
                        send(owner, {:phone_transcript, token, leg_id, transcript})

                      _other ->
                        :ok
                    end

                    state
                  end, nil}
               )
    end

    caller_id = Map.fetch!(proof.plan.participants, "caller").participant_id
    support_id = Map.fetch!(proof.plan.participants, "human-support").participant_id
    incoming_id = proof.incoming_id
    outgoing_id = proof.outgoing_id

    request =
      if proof.provider == :telnyx, do: "request-telnyx-harness", else: "request-twilio-harness"

    deliver_transcript(proof.caller_stt, request, 3, "Caller after transfer.")
    deliver_transcript(proof.support_stt, "phone-support-ready", 1, "Support after transfer.")

    assert_receive {:phone_transcript, ^token, ^incoming_id,
                    %{participant_id: ^support_id, text: "Support after transfer.", final: true}},
                   2_000

    assert_receive {:phone_transcript, ^token, ^outgoing_id,
                    %{participant_id: ^caller_id, text: "Caller after transfer.", final: true}},
                   2_000

    refute_receive {:test_agent_runtime_stream, _, _}, 0
  end

  defp deliver_transcript(transport, request, sequence, text) do
    for {event, offset} <- [{"StartOfTurn", 0}, {"EndOfTurn", 1}] do
      TestSpeechToTextTransport.deliver(
        transport,
        JSON.encode!(%{
          type: "TurnInfo",
          request_id: request,
          sequence_id: sequence + offset,
          event: event,
          turn_index: 1,
          audio_window_start: 0.0,
          audio_window_end: 1.0,
          transcript: text,
          words: [],
          end_of_turn_confidence: 0.99,
          trigger: if(event == "EndOfTurn", do: "model")
        })
      )
    end
  end

  defp discard_source_requests do
    receive do
      {:test_agent_runtime_stream, _, %{messages: [%{content: "Route callers safely."} | _]}} ->
        discard_source_requests()
    after
      0 -> :ok
    end
  end

  defp assert_wait(socket, _provider, :silent_all) do
    refute_receive {:test_phone_output, ^socket, _audio}, 150
  end

  defp assert_wait(socket, provider, mode) do
    await_wait(socket, decoder(provider), mode, System.monotonic_time(:millisecond) + 2_000)
  end

  defp await_wait(socket, decoder, mode, deadline) do
    receive do
      {:test_phone_output, ^socket, message} ->
        case media_pcm(message, decoder) do
          {:ok, pcm} ->
            if mode == :defaults or tone?(pcm, 250, rate(decoder)),
              do: :ok,
              else: await_wait(socket, decoder, mode, deadline)

          :other ->
            await_wait(socket, decoder, mode, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> flunk("missing phone wait audio")
    end
  end

  defp cue_mark(socket, decoder, old_marks, cue?, deadline) do
    receive do
      {:test_phone_output, ^socket, message} ->
        case JSON.decode!(message) do
          %{"event" => "mark", "mark" => %{"name" => name}} when cue? ->
            {name, old_marks}

          %{"event" => "mark", "mark" => %{"name" => name}} ->
            assert :ok = TestTelephonySocket.acknowledge_mark(socket, name)
            cue_mark(socket, decoder, [name | old_marks], false, deadline)

          _other ->
            cue? =
              case media_pcm(message, decoder) do
                {:ok, pcm} -> cue? or tone?(pcm, 1_000, rate(decoder))
                :other -> cue?
              end

            cue_mark(socket, decoder, old_marks, cue?, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("missing phone cue drain mark")
    end
  end

  defp await_conversation(socket, decoder, frequency, mode, phase, deadline) do
    receive do
      {:test_phone_output, ^socket, message} ->
        case media_pcm(message, decoder) do
          {:ok, pcm} ->
            cond do
              tone?(pcm, frequency, rate(decoder)) ->
                assert phase == :cue, "phone conversation preceded cue"
                :ok

              tone?(pcm, 1_000, rate(decoder)) ->
                await_conversation(socket, decoder, frequency, mode, :cue, deadline)

              mode == :custom_url and tone?(pcm, 250, rate(decoder)) ->
                assert phase == :waiting, "phone wait followed cue"
                await_conversation(socket, decoder, frequency, mode, phase, deadline)

              true ->
                await_conversation(socket, decoder, frequency, mode, phase, deadline)
            end

          :other ->
            await_conversation(socket, decoder, frequency, mode, phase, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("missing phone conversation audio")
    end
  end

  defp send_tone(socket, provider, stream, frequency, sequence) do
    sample_rate = if provider == :telnyx, do: 16_000, else: 8_000

    encoder =
      if provider == :telnyx,
        do: Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)

    count = div(sample_rate, 50)
    started = System.monotonic_time(:millisecond)
    timestamp = TestTelephonySocket.media_timestamp(socket)

    for index <- 0..4 do
      receive do
      after
        max(started + index * 20 - System.monotonic_time(:millisecond), 0) -> :ok
      end

      pcm = tone(frequency, sample_rate, count)

      {:ok, payload} =
        if provider == :telnyx,
          do: Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, count),
          else: Codec.encode(pcm)

      media = %{
        "track" => "inbound",
        "chunk" => sequence + index,
        "timestamp" =>
          if(provider == :telnyx,
            do: (timestamp + index * 20) * 16,
            else: timestamp + index * 20
          ),
        "payload" => Base.encode64(payload)
      }

      message =
        if provider == :telnyx,
          do: %{
            "event" => "media",
            "stream_id" => stream,
            "sequence_number" => sequence + index,
            "media" => media
          },
          else: %{
            "event" => "media",
            "streamSid" => stream,
            "sequenceNumber" => to_string(sequence + index),
            "media" =>
              media
              |> Map.update!("chunk", &to_string/1)
              |> Map.update!("timestamp", &to_string/1)
          }

      assert {:ok, _socket} =
               TestTelephonySocket.input(socket, {JSON.encode!(message), opcode: :text})
    end
  end

  defp media_pcm(message, decoder) do
    case JSON.decode!(message) do
      %{"event" => "media", "media" => %{"payload" => payload}} ->
        bytes = Base.decode64!(payload)

        case decoder do
          {:opus, native} -> {:ok, Membrane.Opus.Decoder.Native.decode_packet(native, bytes)}
          :pcmu -> Codec.decode(bytes)
        end

      _other ->
        :other
    end
  end

  defp decoder(:telnyx), do: {:opus, Membrane.Opus.Decoder.Native.create(16_000, 1)}
  defp decoder(:twilio), do: :pcmu
  defp rate({:opus, _}), do: 16_000
  defp rate(:pcmu), do: 8_000

  defp tone?(pcm, frequency, sample_rate) do
    samples = for <<sample::little-signed-16 <- pcm>>, do: sample
    energy = Enum.reduce(samples, 0, fn sample, sum -> sum + sample * sample end)

    {real, imaginary} =
      samples
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0.0}, fn {sample, index}, {r, i} ->
        angle = 2 * :math.pi() * frequency * index / sample_rate
        {r + sample * :math.cos(angle), i + sample * :math.sin(angle)}
      end)

    energy > 0 and 2 * (real * real + imaginary * imaginary) / (length(samples) * energy) > 0.65
  end

  defp tone(frequency, rate, count) do
    for sample <- 0..(count - 1), into: <<>> do
      amplitude = round(12_000 * :math.sin(2 * :math.pi() * frequency * sample / rate))
      <<amplitude::little-signed-16>>
    end
  end

  defp wave(frequency) do
    pcm = tone(frequency, 48_000, 9_600)

    format =
      <<1::little-16, 1::little-16, 48_000::little-32, 96_000::little-32, 2::little-16,
        16::little-16>>

    body = "fmt " <> <<16::little-32>> <> format <> "data" <> <<byte_size(pcm)::little-32>> <> pcm
    "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
  end

  defp drain_output(socket) do
    receive do
      {:test_phone_output, ^socket, _} -> drain_output(socket)
    after
      0 -> :ok
    end
  end

  defp assert_private_recordings(caller_id, deadline) do
    receive do
      {:test_recording_chunk, _stream, chunk} ->
        # The initial signed-call check sends one permitted silence frame before
        # transfer. Its asynchronous write may arrive after holding begins.
        assert chunk.source_participant_ids == [caller_id]

        assert Enum.all?(
                 for(<<sample::little-signed-16 <- chunk.payload>>, do: sample),
                 &(abs(&1) <= 32)
               ),
               "private phone audio entered recording"

        assert_private_recordings(caller_id, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :ok
    end
  end
end
