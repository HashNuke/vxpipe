defmodule Vxpipe.CallEngine.Capability.SpeechToTextLegacyBridgeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Capability.SpeechToText.LegacyBridge
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Session}
  alias Vxpipe.CallEngine.TestCloseFailingSpeechToTextTransport
  alias Vxpipe.CallEngine.TestSpeechToTextTransport
  alias Vxpipe.CallEngine.Usage.ProviderContext

  test "retains hosted recognized-audio usage through the semantic bridge" do
    {capability, transport} = start_bridge()
    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000

    assert :ok = SpeechToText.push_audio(capability, audio_frame())
    assert_receive {:vxpipe_usage_observations, ^capability, [started]}, 1_000
    assert started.outcome == :in_progress

    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, "hello"))
    TestSpeechToTextTransport.deliver(transport, turn_message("EndOfTurn", 2, "hello"))

    assert_receive {:vxpipe_usage_observations, ^capability, observations}, 1_000
    assert [audio] = observations
    assert audio.measurement.component == "recognized_audio_duration"
    assert audio.measurement.quantity == 1_000
    assert audio.measurement.provenance == :provider_reported
  end

  test "preserves the hosted transcript size boundary" do
    {capability, transport} = start_bridge()
    text = String.duplicate("a", 65_536)

    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000

    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, text))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :turn_started}}, 1_000

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %{kind: :transcript_updated, text: ^text}},
                   1_000

    TestSpeechToTextTransport.deliver(transport, turn_message("Update", 2, text))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %{kind: :transcript_updated, text: ^text}},
                   1_000

    TestSpeechToTextTransport.deliver(transport, turn_message("EndOfTurn", 3, text))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :turn_ended, text: ^text}}, 1_000
  end

  test "retires the linked hosted transport when input fails" do
    {capability, transport} = start_bridge(send_mode: :manual)
    transport_monitor = Process.monitor(transport)

    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000

    input = Task.async(fn -> SpeechToText.push_audio(capability, audio_frame()) end)
    assert_receive {:test_stt_audio, ^transport, <<1, 2, 3>>}, 1_000
    TestSpeechToTextTransport.allow_audio(transport, {:error, :rejected})

    assert {:error, reason} = Task.await(input, 1_000)
    assert reason in [:policy_denied, :unavailable]
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _reason}, 1_000
  end

  test "retires the linked hosted transport when its close callback fails" do
    {capability, transport} =
      start_bridge(transport_module: TestCloseFailingSpeechToTextTransport)

    transport_monitor = Process.monitor(transport)
    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000

    TestSpeechToTextTransport.disconnect(transport, :closed)
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _reason}, 1_000
  end

  test "direct provider close cannot orphan a transport when its callback fails" do
    {capability, transport} =
      start_bridge(transport_module: TestCloseFailingSpeechToTextTransport)

    transport_monitor = Process.monitor(transport)
    provider = capability |> :sys.get_state() |> Map.fetch!(:session) |> Session.provider()

    assert {:error, :session_failed} = LegacyBridge.close(provider)
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _reason}, 1_000
  end

  test "accepted final evidence drains before provider disconnect closes the session" do
    {capability, transport} = start_bridge()
    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000
    assert :ok = SpeechToText.push_audio(capability, audio_frame())
    assert_receive {:vxpipe_usage_observations, ^capability, [_started]}, 1_000

    provider = capability |> :sys.get_state() |> Map.fetch!(:session) |> Session.provider()
    provider_monitor = Process.monitor(provider)
    capability_monitor = Process.monitor(capability)
    :ok = :sys.suspend(capability)

    try do
      TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, "last words"))
      TestSpeechToTextTransport.deliver(transport, turn_message("EndOfTurn", 2, "last words"))
      TestSpeechToTextTransport.disconnect(transport, :closed)
      assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}, 1_000
      :ok = :sys.resume(capability)

      assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :turn_started}}, 1_000

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :transcript_updated, text: "last words"}},
                     1_000

      assert_receive {:vxpipe_stt_signal, ^capability, _,
                      %{kind: :turn_ended, text: "last words"}},
                     1_000

      assert_receive {:vxpipe_usage_observations, ^capability, [audio]}, 1_000
      assert audio.measurement.component == "recognized_audio_duration"
      assert audio.measurement.quantity == 1_000
      assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :provider_failed}, 1_000
    after
      try do
        :sys.resume(capability)
      catch
        :exit, _reason -> :ok
      end
    end
  end

  defp start_bridge(transport_options \\ []) do
    assert {:ok, provider} =
             Flux.new(
               api_key: "runtime-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())
    scope = CapabilityTree.scope(tree)
    public = LegacyBridge.public_options(Flux, provider)

    transport_module =
      Keyword.get(transport_options, :transport_module, TestSpeechToTextTransport)

    transport_options = Keyword.delete(transport_options, :transport_module)

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant-bridge",
         room_id: "room-bridge",
         incarnation_id: "incarnation-bridge",
         participant_id: "participant-bridge",
         connection_id: "connection-bridge",
         speech_scope: scope,
         provider: {LegacyBridge, public},
         provider_private: [
           provider: Flux,
           config: provider,
           transport: {transport_module, Keyword.merge([observer: self()], transport_options)}
         ],
         transport: nil,
         usage: usage_context()},
        id: make_ref()
      )

    assert_receive {:test_stt_transport_started, transport, _connection}, 1_000
    {capability, transport}
  end

  defp usage_context do
    assert {:ok, provider} =
             ProviderContext.new(
               name: "deepgram",
               model: "flux-general-en",
               integration_id: "bridge-stt"
             )

    [
      call_id: "call-bridge",
      participant_id: "participant-bridge",
      activation_id: nil,
      provider: provider
    ]
  end

  defp audio_frame do
    %AudioFrame{
      tenant_id: "tenant-bridge",
      room_id: "room-bridge",
      incarnation_id: "incarnation-bridge",
      participant_id: "participant-bridge",
      connection_id: "connection-bridge",
      track_id: "track-bridge",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: 0,
      timestamp: 0,
      payload: <<1, 2, 3>>,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp connected_message do
    ~s({"type":"Connected","request_id":"bridge-request","sequence_id":0})
  end

  defp turn_message(event, sequence, text) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "bridge-request",
      "sequence_id" => sequence,
      "event" => event,
      "trigger" => "model",
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => text,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    })
  end
end
