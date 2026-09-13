defmodule Vxpipe.CallEngine.Capability.SpeechToTextTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.TestSpeechToTextTransport
  alias Vxpipe.CallEngine.Usage.ProviderContext

  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]

  test "validates audio and relays normalized provider signals without raw payloads" do
    assert {:ok, provider} =
             Flux.new(
               api_key: "runtime-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             provider: {Flux, provider},
             transport: {TestSpeechToTextTransport, [observer: self()]}
           ]}
      )

    assert_receive {:test_stt_transport_started, transport,
                    %{
                      url: url,
                      headers: [{"Authorization", "Token runtime-secret"}]
                    }}

    refute url =~ "runtime-secret"

    unsupported = audio_frame(identity, codec: :linear16)
    assert {:error, :unsupported_audio} = SpeechToText.push_audio(capability, unsupported)
    refute_receive {:test_stt_audio, ^transport, _audio}

    frame = audio_frame(identity)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:test_stt_audio, ^transport, <<1, 2, 3>>}

    payload = turn_message("StartOfTurn", 1, "hello")
    TestSpeechToTextTransport.deliver(transport, payload)

    assert_receive {:vxpipe_stt_signal, ^capability,
                    %{
                      tenant_id: "tenant-demo",
                      room_id: "room-demo",
                      incarnation_id: "rinc-demo",
                      participant_id: "part-human",
                      connection_id: "conn-demo"
                    }, %Signal{kind: :turn_started, text: "hello", provider_sequence: 1}}

    refute_receive {:vxpipe_stt_signal, ^capability, _, ^payload}
  end

  test "ignores repeated provider sequence numbers and terminates on transport failure" do
    attach_provider_events(:deepgram)
    {capability, transport} = start_capability()
    payload = turn_message("Update", 4, "hello")

    TestSpeechToTextTransport.deliver(transport, payload)
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{provider_sequence: 4}}

    TestSpeechToTextTransport.deliver(transport, payload)
    refute_receive {:vxpipe_stt_signal, ^capability, _, %Signal{provider_sequence: 4}}

    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.disconnect(transport, :closed)

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :transport_closed}, 500

    assert_receive {:telemetry_event, @provider_failure_event, %{count: 1},
                    %{capability: :stt} = metadata},
                   500

    assert metadata == %{capability: :stt, provider: :deepgram, category: :unavailable}

    assert_receive {:DOWN, ^monitor, :process, ^capability, :transport_closed}, 500
  end

  test "does not turn malformed provider messages into domain signals" do
    {capability, transport} = start_capability()
    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.deliver(transport, ~s({"type":"TurnInfo"}))

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :invalid_provider_message}, 500
    assert_receive {:DOWN, ^monitor, :process, ^capability, :invalid_provider_message}, 500
    refute_receive {:vxpipe_stt_signal, ^capability, _, _}
  end

  test "pins each demanded provider session to one policy revision" do
    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    {capability, first_transport} = start_capability()

    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)
    refute_receive {:test_stt_transport_started, _transport, _connection}

    TestSpeechToTextTransport.deliver(first_transport, turn_message("StartOfTurn", 1, "first"))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{provider_sequence: 1, policy_revision: 0}}

    assert :ok = Enforcer.apply(capability, snapshot(1, ["part-human"], %{}, false), 500)
    assert_receive {:test_stt_transport_closed, ^first_transport}
    assert {:error, :policy_denied} = SpeechToText.push_audio(capability, audio_frame(identity))

    routes = %{"part-human" => MapSet.new(["part-recipient"])}

    assert :ok =
             Enforcer.apply(
               capability,
               snapshot(2, ["part-human", "part-recipient"], routes, false),
               500
             )

    assert_receive {:test_stt_transport_started, second_transport, _connection}
    TestSpeechToTextTransport.deliver(second_transport, connected_message("second", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert :ok = SpeechToText.push_audio(capability, audio_frame(identity))
    assert_receive {:test_stt_audio, ^second_transport, <<1, 2, 3>>}

    TestSpeechToTextTransport.deliver(second_transport, turn_message("StartOfTurn", 1, "second"))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{provider_sequence: 1, policy_revision: 2}}

    second_monitor = Process.monitor(second_transport)

    assert :ok =
             Enforcer.apply(
               capability,
               snapshot(3, ["part-human", "part-recipient"], routes, false),
               500
             )

    assert_receive {:DOWN, ^second_monitor, :process, ^second_transport, :shutdown}
    assert_receive {:test_stt_transport_started, third_transport, _connection}
    refute third_transport == second_transport
  end

  test "policy changes do not wait for provider reconnection and cancel superseded starts" do
    observer = self()
    attempts = start_supervised!({Agent, fn -> 0 end})

    before_connect = fn ->
      attempt = Agent.get_and_update(attempts, &{&1, &1 + 1})

      if attempt > 0 do
        send(observer, {:stt_reconnecting, self()})

        receive do
          :connect -> :ok
        end
      end
    end

    {capability, original_transport} =
      start_capability(transport_options: [before_connect: before_connect])

    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)
    assert :ok = Enforcer.apply(capability, snapshot(1, ["part-human"], :unrestricted, true), 500)
    assert_receive {:stt_reconnecting, first_connector}
    first_monitor = Process.monitor(first_connector)
    assert_receive {:test_stt_transport_closed, ^original_transport}

    assert :ok = Enforcer.apply(capability, snapshot(2, ["part-human"], :unrestricted, true), 500)
    assert_receive {:DOWN, ^first_monitor, :process, ^first_connector, :shutdown}
    assert_receive {:stt_reconnecting, second_connector}

    # Old provider callbacks cannot acquire the new interval's permissions.
    send(
      capability,
      {:vxpipe_stt_transport, original_transport,
       {:message, turn_message("EndOfTurn", 10, "old interval")}}
    )

    _ = :sys.get_state(capability)
    refute_receive {:vxpipe_stt_signal, ^capability, _, _}

    send(second_connector, :connect)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    TestSpeechToTextTransport.deliver(replacement, connected_message("replacement", 0))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :connected, policy_revision: 2}}

    second_monitor = Process.monitor(second_connector)
    replacement_monitor = Process.monitor(replacement)
    assert :ok = stop_supervised({SpeechToText, "conn-demo"})
    assert_receive {:DOWN, ^second_monitor, :process, ^second_connector, _reason}
    assert_receive {:DOWN, ^replacement_monitor, :process, ^replacement, _reason}
  end

  test "emits final-turn deltas and retains a failed provider session" do
    {capability, transport} = start_capability(usage: usage_context())

    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)

    TestSpeechToTextTransport.deliver(transport, connected_message("request-1", 0))
    TestSpeechToTextTransport.deliver(transport, turn_message("Update", 1, "Hello"))

    assert_receive {:vxpipe_usage_observations, ^capability, [started]}
    assert started.outcome == :in_progress
    assert started.measurement == nil

    TestSpeechToTextTransport.deliver(transport, turn_message("EndOfTurn", 2, "Hello 👋"))

    assert_receive {:vxpipe_usage_observations, ^capability, observations}
    assert [audio, text] = Enum.sort_by(observations, & &1.measurement.component)
    assert audio.measurement.component == "recognized_audio_duration"
    assert audio.measurement.quantity == 1_000
    assert text.measurement.component == "recognized_text_characters"
    assert text.measurement.quantity == 7

    assert Enum.all?(observations, fn observation ->
             observation.call_id == "call-usage" and
               observation.provider.name == "deepgram" and
               observation.provider.integration_id == "primary-stt" and
               observation.provider.request_id == "request-1" and
               observation.attribution.service_interval_id != nil
           end)

    [first | _rest] = observations
    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.disconnect(transport, :closed)

    assert_receive {:vxpipe_usage_observations, ^capability, [failed]}
    assert failed.outcome == :failed
    assert failed.measurement == nil
    assert failed.attempt_id == first.attempt_id
    assert failed.attribution.service_interval_id == first.attribution.service_interval_id
    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :transport_closed}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :transport_closed}
  end

  test "rotates service intervals and suppresses denied transcript character counts" do
    {capability, first_transport} = start_capability(usage: usage_context())

    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)

    TestSpeechToTextTransport.deliver(first_transport, connected_message("provider-request-1", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    routes = %{"part-human" => MapSet.new(["part-recipient"])}

    assert :ok =
             Enforcer.apply(
               capability,
               snapshot(1, ["part-human", "part-recipient"], routes, false),
               500
             )

    assert_receive {:vxpipe_usage_observations, ^capability, [started, cancelled]}
    assert started.outcome == :in_progress
    assert cancelled.outcome == :cancelled
    assert cancelled.measurement == nil
    assert_receive {:test_stt_transport_started, second_transport, _connection}

    TestSpeechToTextTransport.deliver(
      second_transport,
      connected_message("provider-request-2", 0)
    )

    TestSpeechToTextTransport.deliver(
      second_transport,
      turn_message("EndOfTurn", 1, "not retained")
    )

    assert_receive {:vxpipe_usage_observations, ^capability, [started, audio]}
    assert started.outcome == :in_progress
    assert started.measurement == nil
    assert audio.measurement.component == "recognized_audio_duration"
    assert audio.attempt_id != cancelled.attempt_id

    assert audio.attribution.service_interval_id !=
             cancelled.attribution.service_interval_id
  end

  test "retains a failed session after the transport accepted audio without a provider signal" do
    {capability, transport} = start_capability(usage: usage_context())

    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    assert :ok = SpeechToText.push_audio(capability, audio_frame(identity))
    assert_receive {:test_stt_audio, ^transport, <<1, 2, 3>>}
    assert_receive {:vxpipe_usage_observations, ^capability, [started]}
    assert started.outcome == :in_progress
    assert started.measurement == nil

    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.disconnect(transport, :closed)

    assert_receive {:vxpipe_usage_observations, ^capability, [failed]}
    assert failed.outcome == :failed
    assert failed.measurement == nil
    assert failed.provider.request_id == nil
    assert_receive {:DOWN, ^monitor, :process, ^capability, :transport_closed}
  end

  defp start_capability(options \\ []) do
    assert {:ok, provider} =
             Flux.new(
               api_key: "runtime-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         connection_id: "conn-demo",
         provider: {Flux, provider},
         transport:
           {TestSpeechToTextTransport,
            [observer: self()] ++ Keyword.get(options, :transport_options, [])},
         usage: Keyword.get(options, :usage)}
      )

    assert_receive {:test_stt_transport_started, transport, _connection}
    {capability, transport}
  end

  defp audio_frame(identity, overrides \\ []) do
    fields =
      identity ++
        [
          track_id: "track-audio",
          codec: :opus,
          sample_rate: 48_000,
          channels: 1,
          sequence_number: 12,
          timestamp: 960,
          payload: <<1, 2, 3>>,
          received_at: 1_788_000_000_000
        ]

    struct!(AudioFrame, Keyword.merge(fields, overrides))
  end

  defp turn_message(event, sequence, transcript) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if event == "EndOfTurn", do: Map.put(message, "trigger", "model"), else: message
    JSON.encode!(message)
  end

  defp connected_message(request_id, sequence) do
    JSON.encode!(%{
      "type" => "Connected",
      "request_id" => request_id,
      "sequence_id" => sequence
    })
  end

  defp usage_context do
    assert {:ok, provider} =
             ProviderContext.new(
               name: "deepgram",
               integration_id: "primary-stt",
               model: "flux-general-en"
             )

    [
      call_id: "call-usage",
      participant_id: "part-human",
      activation_id: nil,
      provider: provider
    ]
  end

  defp snapshot(revision, present, transcript_routes, save_transcripts) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(present),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: transcript_routes,
        record_audio: true,
        save_transcripts: save_transcripts
      }
    }
  end

  def handle_telemetry_event(event, measurements, metadata, {test_pid, provider}) do
    if Map.get(metadata, :provider) == provider do
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end
  end

  defp attach_provider_events(provider) do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        @provider_failure_event,
        &__MODULE__.handle_telemetry_event/4,
        {self(), provider}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
