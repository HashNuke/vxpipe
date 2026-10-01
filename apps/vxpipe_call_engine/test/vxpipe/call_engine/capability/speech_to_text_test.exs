defmodule Vxpipe.CallEngine.Capability.SpeechToTextTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.{AudioFrame, Ingress}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.TestSpeechToTextTransport
  alias Vxpipe.CallEngine.Usage.ProviderContext
  alias Vxpipe.CallEngine.Speech.{Allocation, CapabilityTree, Channel}
  alias Vxpipe.CallEngine.SpeechSessionProbe

  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]

  test "local acoustic ends preserve provenance and an older turn while new speech starts" do
    {:ok, descriptor} = Vxpipe.CallEngine.Provider.MorseCodeSTT.Session.configure([])
    descriptor = %{descriptor | endpointing: :local_gap}
    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    capability =
      start_supervised!(
        {SpeechToText,
         [
           tenant_id: "tenant-local-gap",
           room_id: "room-local-gap",
           incarnation_id: "incarnation-local-gap",
           participant_id: "part-human",
           connection_id: "connection-local-gap",
           owner: self(),
           speech_scope: CapabilityTree.scope(tree),
           provider: {SpeechSessionProbe, [descriptor: descriptor]},
           provider_private: [observer: self()]
         ]},
        id: make_ref()
      )

    assert_receive {:probe_initializing, provider, _channel}, 1_000
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}, 1_000
    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)
    first = make_ref()
    second = make_ref()

    for turn <- [first, second] do
      assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: turn]})
      assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started}}, 1_000
    end

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: first, text: "OLDER", endpointing: :local_gap]}
             )

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{
                      kind: :turn_ended,
                      provider_turn_index: 0,
                      turn_ref: ^first,
                      text: "OLDER",
                      trigger: "local_gap"
                    }},
                   1_000

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: second, text: "NEWER", endpointing: :local_gap]}
             )

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{
                      kind: :turn_ended,
                      provider_turn_index: 1,
                      turn_ref: ^second,
                      text: "NEWER",
                      trigger: "local_gap"
                    }},
                   1_000
  end

  test "initial policy without speech demand avoids a preliminary provider connection" do
    initial = snapshot(0, [], :unrestricted, true)
    capability = start_capability_process(initial_policy: initial)
    assert :ok = Enforcer.apply(capability, initial, 1_000)
    refute_receive {:test_stt_transport_started, _transport, _connection}
    assert {:ok, _resource, :preparing} = SpeechToText.readiness(capability)

    assert :ok =
             Enforcer.apply(capability, snapshot(1, ["part-human"], :unrestricted, true), 1_000)

    assert_receive {:test_stt_transport_started, transport, _connection}, 1_000
    assert {:ok, resource, :preparing} = SpeechToText.readiness(capability)
    TestSpeechToTextTransport.deliver(transport, connected_message("initial-demand", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert {:ok, ^resource, :ready} = SpeechToText.readiness(capability)
    refute_receive {:test_stt_transport_started, _, _}
    refute_receive {:test_stt_transport_closed, ^transport}
  end

  test "activity-only demand starts STT and retires it across audio-only revoke and regrant" do
    active = snapshot(0, ["part-human", "part-agent"], %{}, false)

    capability =
      start_capability_process(initial_policy: active, activity_agent_id: "part-agent")

    assert_receive {:test_stt_transport_started, transport, _connection}
    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("activity", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    denied = %{
      active
      | revision: 1,
        effective: %{active.effective | audio_routes: %{}}
    }

    assert :ok = Enforcer.apply(capability, denied, 500)
    assert {:ok, _retired, :preparing} = SpeechToText.readiness(capability)
    refute_receive {:test_stt_transport_started, _, _}

    restored = %{active | revision: 2}
    assert :ok = Enforcer.apply(capability, restored, 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    assert replacement != transport
  end

  test "prepared activity origin stays private until adoption and demand loss discards it" do
    alias Vxpipe.CallEngine.ResolvedCallPlan
    alias Vxpipe.CallEngine.ResolvedCallPlan.{MediaPolicy, Participant}
    alias Vxpipe.CallEngine.MediaPolicy.Authority

    incarnation_id = "rinc-#{System.unique_integer([:positive])}"
    normal = %{MediaPolicy.inherit() | transcript_routes: %{}, save_transcripts: false}

    participants =
      Map.new(["part-human", "part-agent", "observer", "restrictor"], fn id ->
        policy =
          if id == "restrictor",
            do: %{MediaPolicy.inherit() | audio_routes: %{}},
            else: MediaPolicy.inherit()

        {id, struct(Participant, participant_id: id, while_present: policy)}
      end)

    plan = struct(ResolvedCallPlan, media_policy: normal, participants: participants)

    authority =
      start_supervised!(
        Supervisor.child_spec(
          {Authority, plan: plan, incarnation_id: incarnation_id},
          significant: false
        )
      )

    assert {:ok, base} = Authority.admit(authority, "part-human")

    capability =
      start_capability_process(
        initial_policy: base,
        activity_agent_id: "part-agent",
        incarnation_id: incarnation_id
      )

    assert {:ok, ^base} = Authority.register_enforcer(authority, capability)

    options = [
      owner: self(),
      attempt_id: "activity-preparation",
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, "part-agent")
             )

    assert {:ok, %{change: :replace, resources: [resource]} = prepared} =
             SpeechToText.prepare_policy(capability, candidate, options)

    assert_receive {:test_stt_transport_started, transport, _connection}
    monitor = Process.monitor(transport)
    TestSpeechToTextTransport.deliver(transport, connected_message("prepared", 0))
    await_prepared_connection(capability, transport)

    assert {:ok, %{status: :ready, activity_origin: nil}} =
             SpeechToText.input_binding(capability, resource)

    assert {:ok, before_denial} = Authority.admit(authority, "observer")

    assert {:ok, rebased} =
             Authority.preview_presence(
               authority,
               MapSet.put(before_denial.present_participant_ids, "part-agent")
             )

    assert {:ok, %{token: token}} = SpeechToText.prepare_policy(capability, rebased, options)
    assert token == prepared.token

    assert {:ok, denied} = Authority.admit(authority, "restrictor")

    assert Snapshot.interval(before_denial, :speech_to_text, "part-human") ==
             Snapshot.interval(denied, :speech_to_text, "part-human")

    assert {:ok, refreshed} =
             Authority.preview_presence(
               authority,
               MapSet.put(denied.present_participant_ids, "part-agent")
             )

    assert {:ok, %{resources: []}} =
             SpeechToText.prepare_policy(capability, refreshed, options)

    assert_receive {:DOWN, ^monitor, :process, ^transport, _reason}, 1_000

    assert {:ok, reallowed} = Authority.leave(authority, "restrictor")

    assert {:ok, next_candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(reallowed.present_participant_ids, "part-agent")
             )

    next_options = [
      owner: self(),
      attempt_id: "activity-adoption",
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    assert {:ok, %{resources: [next_resource]}} =
             SpeechToText.prepare_policy(capability, next_candidate, next_options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    TestSpeechToTextTransport.deliver(replacement, connected_message("adopted", 0))
    await_prepared_connection(capability, replacement)

    assert {:ok, %{status: :ready, activity_origin: nil}} =
             SpeechToText.input_binding(capability, next_resource)

    assert {:ok, _adopted} =
             Authority.commit_candidate(
               authority,
               next_candidate,
               Keyword.fetch!(next_options, :deadline_ms),
               [capability]
             )

    assert {:ok, %{activity_origin: %{allocation_generation: generation}}} =
             SpeechToText.input_binding(capability)

    assert is_reference(generation)

    assert {:ok, %{activity_origin: %{allocation_generation: ^generation}}} =
             SpeechToText.input_binding(capability, next_resource)
  end

  test "readiness requires the provider acknowledgement and preserves unchanged session evidence" do
    {capability, transport} = start_capability()
    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)

    assert {:ok, %Resource{} = resource, :preparing} = SpeechToText.readiness(capability)
    assert resource.kind == :speech_to_text
    assert resource.scope == {:participant, "part-human"}
    assert resource.binding == "conn-demo"
    assert resource.instance == capability
    assert resource.policy_interval == 0
    refute inspect(resource) =~ "runtime-secret"

    TestSpeechToTextTransport.deliver(transport, connected_message("session", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert {:ok, ^resource, :ready} = SpeechToText.readiness(capability)

    assert :ok =
             Enforcer.apply(
               capability,
               snapshot(1, ["part-human", "part-support"], :unrestricted, true),
               500
             )

    assert {:ok, ^resource, :ready} = SpeechToText.readiness(capability)
    refute_receive {:test_stt_transport_started, _, _}
  end

  test "a replacement STT session needs its own acknowledgement before readiness returns" do
    {capability, transport} = start_capability()
    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("first-session", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)

    assert :ok = Enforcer.apply(capability, snapshot(1, ["part-human"], %{}, false), 500)
    assert {:ok, _disabled, :preparing} = SpeechToText.readiness(capability)

    assert :ok = Enforcer.apply(capability, snapshot(2, ["part-human"], :unrestricted, true), 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    assert {:ok, resource, :preparing} = SpeechToText.readiness(capability)
    assert resource.generation != original.generation
    assert resource.configuration == original.configuration
    assert resource.policy_interval == 2
    assert resource.instance == original.instance

    send(capability, {:vxpipe_stt_transport, transport, {:message, connected_message("late", 1)}})
    assert {:ok, ^resource, :preparing} = SpeechToText.readiness(capability)

    TestSpeechToTextTransport.deliver(replacement, connected_message("new-session", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert {:ok, ^resource, :ready} = SpeechToText.readiness(capability)
  end

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

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             speech_scope: CapabilityTree.scope(tree),
             provider:
               {FluxSession,
                model: provider.model,
                encoding: provider.encoding,
                sample_rate: provider.sample_rate},
             provider_private: [
               config: provider,
               wire_module: TestSpeechToTextTransport,
               wire_options: [observer: self()]
             ]
           ]}
      )

    assert_receive {:test_stt_transport_started, transport,
                    %{
                      url: url,
                      headers: [{"Authorization", "Token runtime-secret"}]
                    }}

    refute url =~ "runtime-secret"

    TestSpeechToTextTransport.deliver(transport, connected_message("direct", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

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
                    }, %Signal{kind: :turn_started, text: ""}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, text: "hello"}}

    refute_receive {:vxpipe_stt_signal, ^capability, _, ^payload}
  end

  test "ignores repeated provider sequence numbers and terminates on provider failure" do
    attach_provider_events(:deepgram)
    {capability, transport} = start_capability()
    TestSpeechToTextTransport.deliver(transport, connected_message("duplicates", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    payload = turn_message("StartOfTurn", 4, "hello")

    TestSpeechToTextTransport.deliver(transport, payload)
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started}}
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :transcript_updated}}

    TestSpeechToTextTransport.deliver(transport, payload)
    refute_receive {:vxpipe_stt_signal, ^capability, _, _}

    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.disconnect(transport, :closed)

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :provider_failed}, 500

    assert_receive {:telemetry_event, @provider_failure_event, %{count: 1},
                    %{capability: :stt} = metadata},
                   500

    assert metadata == %{capability: :stt, provider: :deepgram, category: :unavailable}

    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}, 500
  end

  test "does not turn malformed provider messages into domain signals" do
    {capability, transport} = start_capability()
    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.deliver(transport, ~s({"type":"TurnInfo"}))

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :provider_failed}, 500
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}, 500
    refute_receive {:vxpipe_stt_signal, ^capability, _, _}
  end

  test "keeps the provider session and sequence when unrelated policies or membership change" do
    {capability, transport} = start_capability()
    initial = snapshot(0, ["part-human"], :unrestricted, true)
    assert :ok = Enforcer.apply(capability, initial, 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("retained", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 4, "before"))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{policy_revision: 0}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, policy_revision: 0}}

    joined = snapshot(1, ["part-human", "part-support"], :unrestricted, true)
    assert :ok = Enforcer.apply(capability, joined, 500)
    audio_only = %{joined | revision: 2, effective: %{joined.effective | audio_routes: %{}}}
    assert :ok = Enforcer.apply(capability, audio_only, 500)

    refute_receive {:test_stt_transport_closed, ^transport}
    refute_receive {:test_stt_transport_started, _, _}
    TestSpeechToTextTransport.deliver(transport, turn_message("Update", 4, "duplicate"))
    TestSpeechToTextTransport.deliver(transport, turn_message("EndOfTurn", 5, "after"))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :turn_ended, policy_revision: 0}}

    refute_receive {:vxpipe_stt_signal, ^capability, _, %Signal{provider_sequence: 4}}
  end

  test "selected activity STT resets its provider on audio-route loss despite transcript demand" do
    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)

    capability =
      start_capability_process(initial_policy: active, activity_agent_id: "part-agent")

    assert_receive {:test_stt_transport_started, first, _connection}
    assert :ok = Enforcer.apply(capability, active, 500)

    denied = %{active | revision: 1, effective: %{active.effective | audio_routes: %{}}}
    assert :ok = Enforcer.apply(capability, denied, 500)
    assert_receive {:test_stt_transport_started, second, _connection}, 1_000
    assert second != first

    restored = %{active | revision: 2}
    assert :ok = Enforcer.apply(capability, restored, 500)
    assert_receive {:test_stt_transport_started, third, _connection}, 1_000
    assert third != second

    unrelated = %{
      restored
      | revision: 3,
        effective: %{restored.effective | record_audio: false}
    }

    assert :ok = Enforcer.apply(capability, unrelated, 500)
    assert_receive {:test_stt_transport_started, fourth, _connection}
    assert fourth != third
  end

  test "selected STT activity signals retain native origin and source audio intervals" do
    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)

    capability =
      start_capability_process(initial_policy: active, activity_agent_id: "part-agent")

    assert_receive {:test_stt_transport_started, first, _connection}
    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(first, connected_message("first", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    TestSpeechToTextTransport.deliver(first, turn_message("StartOfTurn", 1, "old"))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started} = old_start}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated} = old_text}

    old_generation = old_start.allocation_generation
    old_turn = old_start.turn_ref
    assert is_reference(old_generation)
    assert is_reference(old_turn)
    assert old_text.allocation_generation == old_generation
    assert old_text.turn_ref == old_turn
    assert old_start.audio_input_interval == 0
    assert old_start.audio_output_interval == 0

    unrelated = %{
      active
      | revision: 1,
        present_participant_ids: MapSet.new(["part-human", "part-agent", "part-support"])
    }

    assert :ok = Enforcer.apply(capability, unrelated, 500)
    refute_receive {:test_stt_transport_started, _, _}
    TestSpeechToTextTransport.deliver(first, turn_message("Update", 2, "updated"))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated} = rebased}

    assert rebased.allocation_generation == old_generation
    assert rebased.turn_ref == old_turn
    assert rebased.audio_input_interval == 0
    assert rebased.audio_output_interval == 0

    TestSpeechToTextTransport.deliver(first, turn_message("EndOfTurn", 3, "old final"))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_ended} = old_end}
    assert old_end.allocation_generation == old_generation
    assert old_end.turn_ref == old_turn

    denied = %{unrelated | revision: 2, effective: %{unrelated.effective | audio_routes: %{}}}
    assert :ok = Enforcer.apply(capability, denied, 500)
    assert_receive {:test_stt_transport_started, denied_provider, _connection}
    assert denied_provider != first

    restored = %{unrelated | revision: 3}
    assert :ok = Enforcer.apply(capability, restored, 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    assert replacement != denied_provider
    TestSpeechToTextTransport.deliver(replacement, connected_message("replacement", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    TestSpeechToTextTransport.deliver(replacement, turn_message("StartOfTurn", 1, "new"))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started} = fresh}

    assert fresh.allocation_generation != old_generation
    assert fresh.turn_ref != old_turn
    assert fresh.audio_input_interval > 0
    assert fresh.audio_output_interval > 0
    assert old_start.audio_input_interval == 0
    assert old_start.audio_output_interval == 0
  end

  test "selected STT input binding exposes only its current authorized activity origin" do
    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)
    capability = start_capability_process(initial_policy: active, activity_agent_id: "part-agent")
    assert_receive {:test_stt_transport_started, first, _connection}
    assert :ok = Enforcer.apply(capability, active, 500)
    assert {:ok, %{activity_origin: nil}} = SpeechToText.input_binding(capability)
    TestSpeechToTextTransport.deliver(first, connected_message("first", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    assert {:ok,
            %{
              activity_origin: %{
                allocation_generation: first_generation,
                audio_input_interval: 0,
                audio_output_interval: 0,
                agent_id: "part-agent"
              }
            }} = SpeechToText.input_binding(capability)

    assert is_reference(first_generation)

    unrelated = %{
      active
      | revision: 1,
        present_participant_ids: MapSet.new(["part-human", "part-agent", "part-support"])
    }

    assert :ok = Enforcer.apply(capability, unrelated, 500)

    assert {:ok, %{activity_origin: %{allocation_generation: ^first_generation}}} =
             SpeechToText.input_binding(capability)

    denied = %{unrelated | revision: 2, effective: %{unrelated.effective | audio_routes: %{}}}
    assert :ok = Enforcer.apply(capability, denied, 500)
    assert {:ok, %{activity_origin: nil}} = SpeechToText.input_binding(capability)
    assert_receive {:test_stt_transport_started, denied_provider, _connection}, 1_000

    restored = %{unrelated | revision: 3}
    assert :ok = Enforcer.apply(capability, restored, 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    assert replacement != denied_provider
    provider = :sys.get_state(replacement).owner
    _ = :sys.get_state(provider)
    TestSpeechToTextTransport.deliver(replacement, connected_message("replacement", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    assert {:ok,
            %{
              activity_origin: %{
                allocation_generation: next_generation,
                audio_input_interval: input_interval,
                audio_output_interval: output_interval
              }
            }} =
             SpeechToText.input_binding(capability)

    assert is_reference(next_generation) and next_generation != first_generation
    assert input_interval > 0 and output_interval > 0
  end

  test "ready transcript-only STT has no activity controller origin" do
    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)
    capability = start_capability_process(initial_policy: active)
    assert_receive {:test_stt_transport_started, transport, _connection}
    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("transcript-only", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    assert {:ok, %{status: :ready, activity_origin: nil}} =
             SpeechToText.input_binding(capability)
  end

  test "canceled native STT allocation cannot remain the current activity origin" do
    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)

    {capability, transport} =
      start_capability(initial_policy: active, activity_agent_id: "part-agent")

    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("canceled-origin", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    session = :sys.get_state(capability).session
    control = session.scope.control
    channel = GenServer.whereis(Channel.address(session))
    monitor = Process.monitor(channel)

    assert :ok = :sys.suspend(control)

    try do
      TestSpeechToTextTransport.disconnect(transport, :closed)
      assert_receive {:DOWN, ^monitor, :process, ^channel, _reason}, 1_000
      refute Allocation.valid?(session)

      assert {:ok, %{status: :ready, activity_origin: nil}} =
               SpeechToText.input_binding(capability)
    after
      assert :ok = :sys.resume(control)
    end
  end

  test "a selected STT native end queued before an audio-interval change cannot inherit the new interval" do
    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)

    {capability, transport} =
      start_capability(initial_policy: active, activity_agent_id: "part-agent")

    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("old", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, "old"))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started} = started}
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :transcript_updated}}

    previous = :sys.get_state(capability)
    provider = :sys.get_state(transport).owner
    recording_off = %{active | revision: 1, effective: %{active.effective | record_audio: false}}
    assert :ok = :sys.suspend(capability)

    {request, native} =
      try do
        request =
          :gen.send_request(
            capability,
            :"$gen_call",
            {:vxpipe_apply_media_policy, recording_off}
          )

        TestSpeechToTextTransport.deliver(transport, turn_message("EndOfTurn", 2, "old end"))
        _ = :sys.get_state(transport)
        _ = :sys.get_state(provider)
        {:messages, messages} = Process.info(capability, :messages)

        assert {:vxpipe_speech, native} =
                 Enum.find(messages, fn
                   {:vxpipe_speech, %{kind: :turn_ended}} -> true
                   _ -> false
                 end)

        assert native.generation == started.allocation_generation
        assert native.turn_ref == started.turn_ref
        assert :sys.get_state(capability).session == previous.session
        {request, native}
      after
        :sys.resume(capability)
      end

    assert {:reply, :ok} = :gen.receive_response(request, 1_000)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    assert replacement != transport
    assert :sys.get_state(capability).session != previous.session
    native_turn = native.turn_ref
    refute_receive {:vxpipe_stt_signal, ^capability, _, %Signal{turn_ref: ^native_turn}}
  end

  test "an STT ingress envelope admitted before route loss cannot enter the replacement provider" do
    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)

    capability =
      start_capability_process(initial_policy: active, activity_agent_id: "part-agent")

    assert_receive {:test_stt_transport_started, first, _connection}
    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(first, connected_message("first", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert {:ok, %{activity_origin: first_origin}} = SpeechToText.input_binding(capability)
    assert is_reference(first_origin.allocation_generation)

    frame = audio_frame(identity)

    ingress =
      start_supervised!(
        {Ingress,
         identity ++
           [
             capability: self(),
             owner: self(),
             activity_agent_id: "part-agent",
             maximum_age_ms: 1_000,
             maximum_bytes: 32,
             maximum_frames: 2,
             maximum_consecutive_overflows: 2,
             clock: fn -> frame.received_at - 1 end
           ]}
      )

    assert :ok = Enforcer.apply(ingress, active, 500)
    assert :ok = Ingress.bind_audio_origin(ingress, first_origin)
    assert :ok = Ingress.push(ingress, frame)
    assert_receive {:vxpipe_stt_audio, ^ingress, reference, ^frame, intervals}

    assert intervals == %{
             speech_to_text: 0,
             input: 0,
             output: 0,
             allocation_generation: first_origin.allocation_generation
           }

    denied = %{active | revision: 1, effective: %{active.effective | audio_routes: %{}}}
    assert :ok = Enforcer.apply(capability, denied, 500)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    assert replacement != first
    TestSpeechToTextTransport.deliver(replacement, connected_message("replacement", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    send(capability, {:vxpipe_stt_audio, ingress, reference, frame, intervals})
    _ = :sys.get_state(capability)
    refute_receive {:test_stt_audio, ^replacement, _payload}

    send(capability, {:vxpipe_stt_audio, ingress, make_ref(), frame, nil})
    _ = :sys.get_state(capability)
    refute_receive {:test_stt_audio, ^replacement, _payload}

    assert :ok = Enforcer.apply(ingress, denied, 500)
    assert :ok = Ingress.push(ingress, audio_frame(identity, sequence_number: 13))
    refute_receive {:vxpipe_stt_audio, ^ingress, _, _, _}

    restored = %{active | revision: 2}
    assert :ok = Enforcer.apply(capability, restored, 500)
    assert_receive {:test_stt_transport_started, current, _connection}
    assert current != replacement
    TestSpeechToTextTransport.deliver(current, connected_message("current", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert {:ok, %{activity_origin: current_origin}} = SpeechToText.input_binding(capability)
    assert current_origin.allocation_generation != first_origin.allocation_generation

    assert :ok = Enforcer.apply(ingress, restored, 500)
    assert :ok = Ingress.bind_audio_origin(ingress, current_origin)
    fresh = audio_frame(identity, sequence_number: 13, payload: <<4, 5, 6>>)
    assert :ok = Ingress.push(ingress, fresh)
    assert_receive {:vxpipe_stt_audio, ^ingress, fresh_reference, ^fresh, fresh_intervals}

    assert fresh_intervals == %{
             speech_to_text: 0,
             input: current_origin.audio_input_interval,
             output: current_origin.audio_output_interval,
             allocation_generation: current_origin.allocation_generation
           }

    send(capability, {:vxpipe_stt_audio, ingress, fresh_reference, fresh, fresh_intervals})
    assert_receive {:test_stt_audio, ^current, <<4, 5, 6>>}
  end

  test "selected STT accepts only its current native generation on PCM envelopes" do
    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    active = snapshot(0, ["part-human", "part-agent"], :unrestricted, true)

    {capability, transport} =
      start_capability(initial_policy: active, activity_agent_id: "part-agent")

    assert :ok = Enforcer.apply(capability, active, 500)
    TestSpeechToTextTransport.deliver(transport, connected_message("generation-required", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    frame = audio_frame(identity)
    reference = make_ref()
    intervals = %{speech_to_text: 0, input: 0, output: 0}
    assert :ok = SpeechToText.deliver_audio(capability, self(), reference, frame, intervals)

    assert_receive {:vxpipe_stt_audio_result, ^capability, ^reference, 12,
                    {:error, :policy_denied}}

    refute_receive {:test_stt_audio, ^transport, _payload}

    stale_reference = make_ref()

    assert :ok =
             SpeechToText.deliver_audio(
               capability,
               self(),
               stale_reference,
               frame,
               Map.put(intervals, :allocation_generation, make_ref())
             )

    assert_receive {:vxpipe_stt_audio_result, ^capability, ^stale_reference, 12,
                    {:error, :policy_denied}}

    refute_receive {:test_stt_audio, ^transport, _payload}

    assert {:ok, %{activity_origin: %{allocation_generation: generation}}} =
             SpeechToText.input_binding(capability)

    accepted_reference = make_ref()

    assert :ok =
             SpeechToText.deliver_audio(
               capability,
               self(),
               accepted_reference,
               frame,
               Map.put(intervals, :allocation_generation, generation)
             )

    assert_receive {:test_stt_audio, ^transport, <<1, 2, 3>>}
    assert_receive {:vxpipe_stt_audio_result, ^capability, ^accepted_reference, 12, :ok}
  end

  test "pins each demanded provider session to its transcript permission interval" do
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

    TestSpeechToTextTransport.deliver(first_transport, connected_message("first", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    TestSpeechToTextTransport.deliver(first_transport, turn_message("StartOfTurn", 1, "first"))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :turn_started, policy_revision: 0}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, policy_revision: 0}}

    first_monitor = Process.monitor(first_transport)
    assert :ok = Enforcer.apply(capability, snapshot(1, ["part-human"], %{}, false), 500)
    assert_receive {:DOWN, ^first_monitor, :process, ^first_transport, _reason}
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
                    %Signal{kind: :turn_started, policy_revision: 2}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, policy_revision: 2}}

    second_monitor = Process.monitor(second_transport)

    assert :ok =
             Enforcer.apply(
               capability,
               snapshot(3, ["part-human", "part-recipient"], :unrestricted, false),
               500
             )

    assert_receive {:DOWN, ^second_monitor, :process, ^second_transport, _reason}
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
    original_monitor = Process.monitor(original_transport)
    assert :ok = Enforcer.apply(capability, snapshot(1, ["part-human"], %{}, true), 500)
    assert_receive {:stt_reconnecting, first_wire}
    first_monitor = Process.monitor(first_wire)
    assert_receive {:DOWN, ^original_monitor, :process, ^original_transport, _reason}

    assert :ok = Enforcer.apply(capability, snapshot(2, ["part-human"], :unrestricted, true), 500)
    assert_receive {:DOWN, ^first_monitor, :process, ^first_wire, _reason}
    assert_receive {:stt_reconnecting, second_wire}

    # Old provider callbacks cannot acquire the new interval's permissions.
    TestSpeechToTextTransport.deliver(
      original_transport,
      turn_message("EndOfTurn", 10, "old interval")
    )

    _ = :sys.get_state(capability)
    refute_receive {:vxpipe_stt_signal, ^capability, _, _}

    send(second_wire, :connect)
    assert_receive {:test_stt_transport_started, replacement, _connection}
    TestSpeechToTextTransport.deliver(replacement, connected_message("replacement", 0))

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :connected, policy_revision: 2}}

    second_monitor = Process.monitor(second_wire)
    replacement_monitor = Process.monitor(replacement)
    assert :ok = stop_supervised({SpeechToText, "conn-demo"})
    assert_receive {:DOWN, ^second_monitor, :process, ^second_wire, _reason}
    assert_receive {:DOWN, ^replacement_monitor, :process, ^replacement, _reason}
  end

  test "emits final-turn deltas and retains a failed provider session" do
    {capability, transport} = start_capability(usage: usage_context())

    assert :ok = Enforcer.apply(capability, snapshot(0, ["part-human"], :unrestricted, true), 500)

    TestSpeechToTextTransport.deliver(transport, connected_message("request-1", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, "Hello"))

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
    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :provider_failed}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}
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

    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    TestSpeechToTextTransport.deliver(
      second_transport,
      turn_message("StartOfTurn", 1, "not retained")
    )

    TestSpeechToTextTransport.deliver(
      second_transport,
      turn_message("EndOfTurn", 2, "not retained")
    )

    assert_receive {:vxpipe_usage_observations, ^capability, [started]}
    assert_receive {:vxpipe_usage_observations, ^capability, [audio]}
    assert started.outcome == :in_progress
    assert started.measurement == nil
    assert audio.measurement.component == "recognized_audio_duration"
    assert audio.attempt_id != cancelled.attempt_id

    assert audio.attribution.service_interval_id !=
             cancelled.attribution.service_interval_id
  end

  test "retains a failed session after the provider accepted audio without a signal" do
    {capability, transport} = start_capability(usage: usage_context())

    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    TestSpeechToTextTransport.deliver(transport, connected_message("accepted-audio", 0))
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

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
    assert failed.provider.request_id == "accepted-audio"
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}
  end

  test "async ingress receives final evidence before a failed native input closes the capability" do
    assert {:module, SpeechSessionProbe} = Code.ensure_loaded(SpeechSessionProbe)

    identity = [
      tenant_id: "tenant-native-failure",
      room_id: "room-native-failure",
      incarnation_id: "incarnation-native-failure",
      participant_id: "part-human",
      connection_id: "conn-native-failure"
    ]

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             speech_scope: CapabilityTree.scope(tree),
             provider: {SpeechSessionProbe, []},
             provider_private: [observer: self(), input_result: :final_then_fail]
           ]},
        id: make_ref()
      )

    assert_receive {:probe_initializing, provider, _channel}, 1_000
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}, 1_000
    policy = snapshot(0, ["part-human"], :unrestricted, true)
    assert :ok = Enforcer.apply(capability, policy, 500)
    assert {:ok, resource, :ready} = SpeechToText.readiness(capability)

    ingress =
      start_supervised!(
        {Ingress,
         identity ++
           [
             capability: capability,
             owner: self(),
             input_admission: :open,
             maximum_age_ms: 1_000,
             maximum_bytes: 65_536,
             maximum_frames: 20,
             maximum_consecutive_overflows: 3
           ]},
        id: make_ref()
      )

    assert :ok = Enforcer.apply(ingress, policy, 500)

    track = %{track_id: "native-track", codec: :linear16, sample_rate: 16_000, channels: 1}
    assert :ok = Ingress.prepare_track(ingress, track, resource)

    frame =
      struct!(
        AudioFrame,
        identity ++
          Map.to_list(track) ++
          [
            sequence_number: 1,
            timestamp: 0,
            payload: <<0, 0>>,
            received_at: System.monotonic_time(:millisecond)
          ]
      )

    monitor = Process.monitor(capability)
    assert :ok = Ingress.push(ingress, frame)
    assert_receive {:probe_input, ^provider}
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, text: "final evidence"}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :turn_ended, text: "final evidence"}}

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :provider_failed}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}
  end

  defp start_capability(options \\ []) do
    capability = start_capability_process(options)
    assert_receive {:test_stt_transport_started, transport, _connection}
    {capability, transport}
  end

  defp start_capability_process(options) do
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

    provider_private = [
      config: provider,
      wire_module: TestSpeechToTextTransport,
      wire_options: [observer: self()] ++ Keyword.get(options, :transport_options, [])
    ]

    start_supervised!(
      {SpeechToText,
       [
         owner: self(),
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: Keyword.get(options, :incarnation_id, "rinc-demo"),
         participant_id: "part-human",
         connection_id: "conn-demo",
         speech_scope: CapabilityTree.scope(tree),
         provider: {FluxSession, provider_options},
         provider_private: provider_private,
         usage: Keyword.get(options, :usage)
       ] ++ Keyword.take(options, [:initial_policy, :activity_agent_id])}
    )
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

  defp await_prepared_connection(capability, transport) do
    provider = :sys.get_state(transport).owner
    _ = :sys.get_state(provider)
    allocation = :sys.get_state(capability).pending_policy.state.session
    channel = GenServer.whereis(Channel.address(allocation))
    _ = :sys.get_state(channel)
    _ = :sys.get_state(capability)
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
