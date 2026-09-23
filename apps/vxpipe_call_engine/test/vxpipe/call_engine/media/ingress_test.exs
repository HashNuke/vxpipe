defmodule Vxpipe.CallEngine.Media.IngressTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.{AudioFrame, Ingress}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.CallEngine.Speech.CapabilityTree
  alias Vxpipe.CallEngine.TestSpeechToTextTransport

  @identity [
    tenant_id: "tenant-demo",
    room_id: "room-demo",
    incarnation_id: "rinc-demo",
    participant_id: "part-human",
    connection_id: "conn-demo"
  ]

  @track %{track_id: "track-audio", codec: :opus, sample_rate: 48_000, channels: 1}

  test "prepares the STT handoff before microphone release without replaying held audio" do
    {capability, transport} = start_capability()
    ingress = start_ingress(capability, input_admission: :closed)
    policy = snapshot(0, ["part-human"], %{}, true)
    assert :ok = Enforcer.apply(capability, policy, 500)
    assert :ok = Enforcer.apply(ingress, policy, 500)
    assert {:ok, _unbound, :preparing} = Ingress.readiness(ingress)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert {:ok, resource, :preparing} = Ingress.readiness(ingress)

    connect_transport(capability, transport)
    assert {:ok, ^resource, :ready} = Ingress.readiness(ingress)
    assert {:ok, [^resource, stt]} = Ingress.readiness_resources(ingress)
    assert stt.instance == capability
    assert stt.kind == :speech_to_text
    assert resource.policy_interval == stt.policy_interval
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))
    assert :ok = Ingress.open(ingress)
    assert {:ok, ^resource, :ready} = Ingress.readiness(ingress)

    assert {:error, :wrong_track} =
             Ingress.push(ingress, audio_frame(2, <<2>>, track_id: "other"))

    assert {:error, :unsupported_audio} =
             Ingress.push(ingress, audio_frame(3, <<3>>, codec: :linear16))

    assert :ok = Ingress.push(ingress, audio_frame(4, <<4>>))
    assert_receive {:test_stt_audio, ^transport, <<4>>}
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 4}}
    refute_receive {:test_stt_audio, ^transport, <<1>>}
    assert {:ok, ^resource, :ready} = Ingress.readiness(ingress)
  end

  test "rejects invalid and incompatible preparations without pinning a track" do
    {capability, _transport} = start_capability()
    ingress = start_ingress(capability)

    assert {:error, :invalid_track} =
             Ingress.prepare_track(ingress, %{track_id: "missing-format"})

    assert {:error, :invalid_track} = Ingress.prepare_track(ingress, %{@track | channels: 0})

    assert {:error, :unsupported_audio} =
             Ingress.prepare_track(ingress, %{@track | codec: :linear16})

    assert {:error, :unsupported_audio} =
             Ingress.prepare_track(ingress, %{@track | sample_rate: 16_000})

    assert :ok = Ingress.prepare_track(ingress, @track)
    assert {:error, :wrong_track} = Ingress.prepare_track(ingress, %{@track | track_id: "other"})

    assert {:error, :track_already_prepared} =
             Ingress.prepare_track(ingress, %{@track | channels: 2})
  end

  test "does not prepare a provider belonging to another room incarnation" do
    {capability, _transport} = start_capability()
    ingress = start_ingress(capability, incarnation_id: "rinc-other")
    assert {:error, :wrong_connection} = Ingress.prepare_track(ingress, @track)
    assert {:ok, _resource, :failed} = Ingress.readiness(ingress)
  end

  test "preserves readiness bindings and queued work across unrelated policy changes" do
    {capability, transport} = start_capability(send_mode: :manual)
    ingress = start_ingress(capability, maximum_frames: 1)
    policy = snapshot(0, ["part-human"], %{}, true)
    assert :ok = Enforcer.apply(capability, policy, 500)
    assert :ok = Enforcer.apply(ingress, policy, 500)
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert {:ok, resource, :ready} = Ingress.readiness(ingress)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))
    assert_receive {:test_stt_audio, ^transport, <<1>>}
    assert :ok = Ingress.prepare_track(ingress, @track)
    # The provider is deliberately busy until its send is acknowledged.
    changed = %{policy | revision: 1, effective: %{policy.effective | record_audio: false}}
    assert :ok = Enforcer.apply(ingress, changed, 500)
    assert {:error, :queue_full} = Ingress.push(ingress, audio_frame(2, <<2>>))
    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 1}}
    assert :ok = Enforcer.apply(capability, changed, 500)
    assert {:ok, ^resource, :ready} = Ingress.readiness(ingress)
    refute_receive {:test_stt_transport_started, _replacement, _connection}

    required = snapshot(2, ["part-human", "part-recipient"], :unrestricted, true)
    assert :ok = Enforcer.apply(ingress, required, 500)
    assert {:ok, changed_resource, :preparing} = Ingress.readiness(ingress)
    assert changed_resource.policy_interval == 2
    assert changed_resource.generation == resource.generation
  end

  test "keeps activity-only microphone demand and removes it on audio-route revocation" do
    ingress = start_ingress(self(), activity_agent_id: "part-agent")
    active = snapshot(0, ["part-human", "part-agent"], %{}, false)
    first_generation = make_ref()

    first_origin = %{
      allocation_generation: first_generation,
      audio_input_interval: 0,
      audio_output_interval: 0,
      agent_id: "part-agent"
    }

    assert :ok = Enforcer.apply(ingress, active, 500)
    assert :ok = Ingress.bind_audio_origin(ingress, first_origin)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))

    assert_receive {:vxpipe_stt_audio, ^ingress, _, _,
                    %{allocation_generation: ^first_generation, input: 0, output: 0}}

    denied = %{active | revision: 1, effective: %{active.effective | audio_routes: %{}}}
    assert :ok = Enforcer.apply(ingress, denied, 500)
    assert :ok = Ingress.push(ingress, audio_frame(2, <<2>>))
    refute_receive {:vxpipe_stt_audio, ^ingress, _, _, _}

    restored = %{active | revision: 2}
    assert :ok = Enforcer.apply(ingress, restored, 500)
    next_generation = make_ref()
    policy = :sys.get_state(ingress).policy
    next_input = Snapshot.interval(policy, :audio_input, "part-human")
    next_output = Snapshot.interval(policy, :audio_output, "part-human")

    assert :ok =
             Ingress.bind_audio_origin(ingress, %{
               first_origin
               | allocation_generation: next_generation,
                 audio_input_interval: next_input,
                 audio_output_interval: next_output
             })

    assert :ok = Ingress.push(ingress, audio_frame(3, <<3>>))

    assert_receive {:vxpipe_stt_audio, ^ingress, _, _,
                    %{
                      allocation_generation: ^next_generation,
                      input: ^next_input,
                      output: ^next_output
                    }}
  end

  test "selected activity ingress remains closed without a bound native origin" do
    ingress = start_ingress(self(), activity_agent_id: "part-agent")
    active = snapshot(0, ["part-human", "part-agent"], %{}, false)
    assert :ok = Enforcer.apply(ingress, active, 500)

    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))
    refute_receive {:vxpipe_stt_audio, ^ingress, _, _, _}
  end

  test "selected ingress readiness waits for its bound current audio origin" do
    {capability, transport} = start_capability([], "part-agent")
    ingress = start_ingress(capability, activity_agent_id: "part-agent")
    active = snapshot(0, ["part-human", "part-agent"], %{}, false)

    assert :ok = Enforcer.apply(capability, active, 500)
    assert :ok = Enforcer.apply(ingress, active, 500)
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)

    assert {:ok, _resource, :preparing} = Ingress.readiness(ingress)

    assert {:ok, %{activity_origin: origin}} = SpeechToText.input_binding(capability)
    assert is_reference(origin.allocation_generation)
    assert :ok = Ingress.bind_audio_origin(ingress, origin)
    assert {:ok, _resource, :ready} = Ingress.readiness(ingress)
  end

  test "selected ingress readiness detects stale native generation with unchanged intervals" do
    {capability, transport} = start_capability([], "part-agent")
    ingress = start_ingress(capability, activity_agent_id: "part-agent")
    active = snapshot(0, ["part-human", "part-agent"], %{}, false)

    assert :ok = Enforcer.apply(capability, active, 500)
    assert :ok = Enforcer.apply(ingress, active, 500)
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert {:ok, %{activity_origin: first}} = SpeechToText.input_binding(capability)
    assert :ok = Ingress.bind_audio_origin(ingress, first)
    assert {:ok, _resource, :ready} = Ingress.readiness(ingress)

    stale = %{first | allocation_generation: make_ref()}
    assert :ok = Ingress.bind_audio_origin(ingress, stale)
    assert {:ok, _resource, :preparing} = Ingress.readiness(ingress)
  end

  test "selected ingress stays preparing until a same-interval replacement is rebound" do
    {capability, transport} = start_capability([], "part-agent")
    ingress = start_ingress(capability, activity_agent_id: "part-agent")
    active = snapshot(0, ["part-human", "part-agent"], %{}, true)

    assert :ok = Enforcer.apply(capability, active, 500)
    assert :ok = Enforcer.apply(ingress, active, 500)
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert {:ok, %{audio_origin: first}} = SpeechToText.input_binding(capability)
    assert :ok = Ingress.bind_audio_origin(ingress, first)
    assert {:ok, _resource, :ready} = Ingress.readiness(ingress)

    changed = %{active | revision: 1, present_participant_ids: MapSet.new(["part-human"])}
    assert :ok = Enforcer.apply(capability, changed, 500)
    assert :ok = Enforcer.apply(ingress, changed, 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    connect_transport(capability, replacement)

    assert {:ok, %{activity_origin: nil, audio_origin: second}} =
             SpeechToText.input_binding(capability)

    assert first.allocation_generation != second.allocation_generation
    assert first.audio_input_interval == second.audio_input_interval
    assert first.audio_output_interval == second.audio_output_interval
    assert {:ok, _resource, :preparing} = Ingress.readiness(ingress)

    assert :ok = Ingress.bind_audio_origin(ingress, second)
    assert {:ok, _resource, :ready} = Ingress.readiness(ingress)
  end

  test "selected ingress keeps transcription audio after reverse route denial" do
    {capability, transport} = start_capability([], "part-agent")
    ingress = start_ingress(capability, activity_agent_id: "part-agent")
    active = snapshot(0, ["part-human", "part-agent"], %{}, true)

    assert :ok = Enforcer.apply(capability, active, 500)
    assert :ok = Enforcer.apply(ingress, active, 500)
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert {:ok, %{activity_origin: first}} = SpeechToText.input_binding(capability)
    assert :ok = Ingress.bind_audio_origin(ingress, first)

    caller_only = %{
      active
      | revision: 1,
        effective: %{
          active.effective
          | audio_routes: %{"part-human" => MapSet.new(["part-agent"])}
        }
    }

    assert :ok = Enforcer.apply(capability, caller_only, 500)
    assert :ok = Enforcer.apply(ingress, caller_only, 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    connect_transport(capability, replacement)

    assert {:ok, %{activity_origin: nil, audio_origin: audio_origin}} =
             SpeechToText.input_binding(capability)

    assert is_reference(audio_origin.allocation_generation)
    assert :ok = Ingress.bind_audio_origin(ingress, audio_origin)
    assert {:ok, _resource, :ready} = Ingress.readiness(ingress)
    assert :ok = Ingress.push(ingress, audio_frame(22, <<22>>))
    assert_receive {:test_stt_audio, ^replacement, <<22>>}
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 22}}
  end

  test "bounds queued audio while preserving accepted frame order" do
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 2,
             maximum_bytes: 6,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 3,
             clock: fn -> 1_000 end
           ]}
      )

    connect_transport(capability, transport)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1, 1, 1>>))
    assert_receive {:test_stt_audio, ^transport, <<1, 1, 1>>}

    assert :ok = Ingress.push(ingress, audio_frame(2, <<2, 2, 2>>))
    assert {:error, :queue_full} = Ingress.push(ingress, audio_frame(3, <<3>>))

    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:test_stt_audio, ^transport, <<2, 2, 2>>}

    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 2}}
  end

  test "rejects stale and wrongly scoped frames before provider delivery" do
    {capability, transport} = start_capability()

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 2,
             maximum_bytes: 32,
             maximum_age_ms: 100,
             maximum_consecutive_overflows: 2,
             clock: fn -> 1_000 end
           ]}
      )

    assert {:error, :stale_frame} =
             Ingress.push(ingress, audio_frame(1, <<1>>, received_at: 899))

    assert {:error, :wrong_connection} =
             Ingress.push(ingress, audio_frame(2, <<2>>, connection_id: "conn-other"))

    refute_receive {:test_stt_audio, ^transport, _audio}
  end

  test "binds the stream to the first accepted audio track" do
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             maximum_frames: 2,
             maximum_bytes: 32,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 2,
             clock: fn -> 1_000 end
           ]}
      )

    connect_transport(capability, transport)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))
    assert_receive {:test_stt_audio, ^transport, <<1>>}

    assert {:error, :wrong_track} =
             Ingress.push(ingress, audio_frame(2, <<2>>, track_id: "track-other"))
  end

  test "drops a queued frame that ages out before delivery" do
    clock = start_supervised!({Agent, fn -> 1_000 end})
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 2,
             maximum_bytes: 6,
             maximum_age_ms: 100,
             maximum_consecutive_overflows: 3,
             clock: fn -> Agent.get(clock, & &1) end
           ]}
      )

    connect_transport(capability, transport)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1, 1, 1>>))
    assert_receive {:test_stt_audio, ^transport, <<1, 1, 1>>}
    assert :ok = Ingress.push(ingress, audio_frame(2, <<2, 2, 2>>))

    Agent.update(clock, fn _now -> 1_101 end)
    TestSpeechToTextTransport.allow_audio(transport)

    assert_receive {:vxpipe_media_ingress, ^ingress, {:dropped, :stale, 2}}
    refute_receive {:test_stt_audio, ^transport, <<2, 2, 2>>}
  end

  test "fails the STT stream after sustained overflow" do
    {capability, transport} = start_capability(send_mode: :manual)
    capability_monitor = Process.monitor(capability)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 1,
             maximum_bytes: 3,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 2,
             clock: fn -> 1_000 end
           ]}
      )

    ingress_monitor = Process.monitor(ingress)

    connect_transport(capability, transport)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1, 1, 1>>))
    assert_receive {:test_stt_audio, ^transport, <<1, 1, 1>>}
    assert {:error, :queue_full} = Ingress.push(ingress, audio_frame(2, <<2>>))
    assert {:error, :media_overloaded} = Ingress.push(ingress, audio_frame(3, <<3>>))

    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, :media_overloaded}

    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :media_overloaded}
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :media_overloaded}
  end

  test "purges queued audio and gates later input at each media-policy revision" do
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             maximum_frames: 3,
             maximum_bytes: 32,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 2,
             owner: self(),
             clock: fn -> 1_000 end
           ]}
      )

    connect_transport(capability, transport)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))
    assert_receive {:test_stt_audio, ^transport, <<1>>}
    assert :ok = Ingress.push(ingress, audio_frame(2, <<2>>))

    assert :ok = Enforcer.apply(ingress, snapshot(0, ["part-human"], %{}, false), 500)
    TestSpeechToTextTransport.allow_audio(transport)
    _ = :sys.get_state(ingress)
    refute_receive {:test_stt_audio, ^transport, <<2>>}

    assert :ok = Ingress.push(ingress, audio_frame(3, <<3>>))
    refute_receive {:test_stt_audio, ^transport, <<3>>}

    routes = %{"part-human" => MapSet.new(["part-recipient"])}

    assert :ok =
             Enforcer.apply(
               ingress,
               snapshot(1, ["part-human", "part-recipient"], routes, false),
               500
             )

    assert :ok = Ingress.push(ingress, audio_frame(4, <<4>>))
    assert_receive {:test_stt_audio, ^transport, <<4>>}
    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 4}}
  end

  test "forwards live microphone audio to the STS target without affecting STT delivery" do
    {capability, transport} = start_capability()
    ingress = start_ingress(capability, sts_target: self())
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<7, 7>>))
    assert_receive {:test_stt_audio, ^transport, <<7, 7>>}
    assert_receive {:vxpipe_ingress_sts_audio, "part-human", <<7, 7>>}
  end

  test "a dead STS target never blocks STT delivery" do
    {capability, transport} = start_capability()
    dead = spawn(fn -> :ok end)
    ingress = start_ingress(capability, sts_target: dead)
    connect_transport(capability, transport)
    assert :ok = Ingress.prepare_track(ingress, @track)
    assert :ok = Ingress.push(ingress, audio_frame(1, <<9>>))
    assert_receive {:test_stt_audio, ^transport, <<9>>}
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 1}}
  end

  defp start_ingress(capability, options \\ []) do
    start_supervised!(
      {Ingress,
       Keyword.merge(
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 3,
             maximum_bytes: 32,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 3,
             clock: fn -> 1_000 end
           ],
         options
       )}
    )
  end

  defp connect_transport(capability, transport) do
    TestSpeechToTextTransport.deliver(
      transport,
      JSON.encode!(%{"type" => "Connected", "request_id" => "prepared-input", "sequence_id" => 0})
    )

    assert_receive {:vxpipe_stt_signal, ^capability, _identity, %{kind: :connected}}
  end

  defp start_capability(transport_options \\ [], activity_agent_id \\ nil) do
    assert {:ok, provider} =
             Flux.new(
               api_key: "runtime-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    provider_options = [
      model: provider.model,
      encoding: provider.encoding,
      sample_rate: provider.sample_rate
    ]

    capability =
      start_supervised!(
        {SpeechToText,
         @identity ++
           [
             owner: self(),
             activity_agent_id: activity_agent_id,
             speech_scope: CapabilityTree.scope(tree),
             provider: {FluxSession, provider_options},
             provider_private: [
               config: provider,
               wire_module: TestSpeechToTextTransport,
               wire_options: Keyword.put(transport_options, :observer, self())
             ]
           ]}
      )

    assert_receive {:test_stt_transport_started, transport, _connection}
    {capability, transport}
  end

  defp audio_frame(sequence, payload, overrides \\ []) do
    fields =
      @identity ++
        [
          track_id: "track-audio",
          codec: :opus,
          sample_rate: 48_000,
          channels: 1,
          sequence_number: sequence,
          timestamp: sequence * 960,
          payload: payload,
          received_at: 1_000
        ]

    struct!(AudioFrame, Keyword.merge(fields, overrides))
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
end
