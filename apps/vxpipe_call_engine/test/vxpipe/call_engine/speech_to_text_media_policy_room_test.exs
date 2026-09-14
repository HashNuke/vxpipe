defmodule Vxpipe.CallEngine.SpeechToTextMediaPolicyRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestCallLifecycleTimer,
    TestSpeechToTextTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, JoinParticipant}
  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux

  test "prepares changed speech policy without replacing the live session until commit" do
    context = preparation_room()
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)
    options = preparation_options()

    assert {:ok, prepared} = SpeechToText.prepare_policy(capability, candidate, options)
    assert prepared.change == :replace
    assert [resource] = prepared.resources
    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    assert {:ok, ^prepared} = SpeechToText.prepare_policy(capability, candidate, options)

    assert {:error, :preparation_conflict} =
             SpeechToText.prepare_policy(
               capability,
               candidate,
               Keyword.update!(options, :deadline_ms, &(&1 + 1_000))
             )

    refute_receive {:test_stt_transport_started, _, _}
    assert Authority.snapshot(context.authority) == candidate.base_snapshot
    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    assert {:error, :policy_not_ready} = Enforcer.apply(capability, candidate.snapshot, 500)
    refute_receive {:test_stt_transport_closed, ^transport}

    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    assert_receive {:test_stt_audio, ^transport, <<1>>}
    refute_receive {:test_stt_audio, ^replacement, _audio}

    collector = collect([resource], context.room.incarnation_id)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :preparing}}, 1_000
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    TestSpeechToTextTransport.deliver(replacement, turn_message("StartOfTurn", 1, "not admitted"))
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "not admitted"}}
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert_receive {:test_stt_transport_closed, ^transport}, 1_000
    refute_receive {:test_stt_transport_started, _, _}
    assert {:ok, committed, :ready} = SpeechToText.readiness(capability)
    assert committed.generation == resource.generation
    assert committed.policy_interval == resource.policy_interval
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
    assert {:error, :stale_preparation} = SpeechToText.discard_policy(capability, prepared.token)
    assert Authority.snapshot(context.authority) == candidate.snapshot
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 2))
    assert_receive {:test_stt_audio, ^replacement, <<1>>}

    send(
      capability,
      {:vxpipe_stt_transport, replacement,
       {:message, turn_message("StartOfTurn", 1, "not admitted")}}
    )

    _ = :sys.get_state(capability)
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "not admitted"}}
  end

  test "discarding a prepared speech policy closes only its replacement session" do
    context = preparation_room()
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(capability, candidate, preparation_options())

    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    monitor = Process.monitor(replacement)
    assert :ok = SpeechToText.discard_policy(capability, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    refute_receive {:test_stt_transport_closed, ^transport}
    assert {:error, :unavailable} = SpeechToText.readiness_binding(hd(prepared.resources))
    assert Authority.snapshot(context.authority) == candidate.base_snapshot
  end

  test "preparing an unrelated policy retains the exact speech session and resource" do
    context = preparation_room(restriction: %{record_audio: false})
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)

    assert {:ok, %{change: :retain, resources: [^original]}} =
             SpeechToText.prepare_policy(capability, candidate, preparation_options())

    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    refute_receive {:test_stt_transport_started, _, _}
    refute_receive {:test_stt_transport_closed, ^transport}
  end

  test "preparing a speech denial keeps the current session until commit" do
    context = preparation_room(restriction: %{transcript_routes: %{}, save_transcripts: false})
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)

    assert {:ok, %{change: :disable, resources: []}} =
             SpeechToText.prepare_policy(capability, candidate, preparation_options())

    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    refute_receive {:test_stt_transport_closed, ^transport}
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert_receive {:test_stt_transport_closed, ^transport}
    refute_receive {:test_stt_transport_started, _, _}
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    refute_receive {:test_stt_audio, _, _}
  end

  test "preparation owner loss cancels only its pending speech session" do
    context = preparation_room()
    owner = start_supervised!({Agent, fn -> :owner end}, id: :preparation_owner)
    options = Keyword.put(preparation_options(), :owner, owner)
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    monitor = Process.monitor(replacement)
    stop_supervised!(:preparation_owner)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:ok, _resource, :failed} = SpeechToText.readiness_binding(hd(prepared.resources))

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.capability, context.candidate.snapshot, 500)
  end

  test "an unrelated membership revision retains and rebinds an already ready replacement" do
    context = preparation_room()
    options = preparation_options()
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    collector = collect(prepared.resources, context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    observer = Map.fetch!(context.plan.participants, "observer")

    join = %{
      context.join
      | id: Vxpipe.CallEngine.Id.generate(:command),
        participant_id: observer.participant_id
    }

    assert {:ok, _participant} = CallEngine.join_participant(join)
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:error, :unavailable} = SpeechToText.readiness_binding(hd(prepared.resources))
    current = Authority.snapshot(context.authority)
    destination = context.join.participant_id

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(current.present_participant_ids, destination)
             )

    assert {:ok, rebound} = SpeechToText.prepare_policy(context.capability, candidate, options)
    assert rebound.token == prepared.token
    before = hd(prepared.resources)
    after_rebase = hd(rebound.resources)
    assert after_rebase.generation == before.generation
    assert after_rebase.configuration == before.configuration
    assert after_rebase.policy_interval != before.policy_interval
    assert {:ok, ^after_rebase, :ready} = SpeechToText.readiness_binding(after_rebase)
    refute_receive {:test_stt_transport_started, _, _}
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert {:ok, committed, :ready} = SpeechToText.readiness(context.capability)
    assert committed.generation == before.generation
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    assert_receive {:test_stt_audio, ^replacement, <<1>>}
  end

  test "preparation deadline closes the pending transport and rejects commit" do
    context = preparation_room()

    options =
      Keyword.put(
        preparation_options(),
        :deadline_ms,
        System.monotonic_time(:millisecond) + 1_000
      )

    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    monitor = Process.monitor(replacement)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_500
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:error, :unavailable} = SpeechToText.readiness_binding(hd(prepared.resources))

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.capability, context.candidate.snapshot, 500)
  end

  test "pending provider failure leaves the source ready and a new attempt rejects old cleanup" do
    context = preparation_room()
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, first} =
             SpeechToText.prepare_policy(
               context.capability,
               context.candidate,
               preparation_options()
             )

    assert_receive {:test_stt_transport_started, replacement, _connection}
    monitor = Process.monitor(replacement)
    TestSpeechToTextTransport.disconnect(replacement, :closed)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:ok, _resource, :failed} = SpeechToText.readiness_binding(hd(first.resources))
    assert :ok = SpeechToText.discard_policy(context.capability, first.token)
    options = Keyword.put(preparation_options(), :attempt_id, "next-policy-attempt")

    assert {:ok, second} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, next, _connection}
    assert second.token != first.token

    assert {:error, :stale_preparation} =
             SpeechToText.discard_policy(context.capability, first.token)

    send(context.capability, {:stt_policy_expired, first.token})
    assert {:ok, _resource, :preparing} = SpeechToText.readiness_binding(hd(second.resources))
    monitor = Process.monitor(next)
    assert :ok = SpeechToText.discard_policy(context.capability, second.token)
    assert_receive {:DOWN, ^monitor, :process, ^next, _reason}, 1_000
  end

  test "rejects a candidate from another authority even when its policy snapshot matches" do
    context = preparation_room()

    other =
      start_supervised!(
        Supervisor.child_spec(
          {Authority, plan: context.plan, incarnation_id: "foreign-policy", register: false},
          significant: false
        )
      )

    assert {:ok, _snapshot} = Authority.admit(other, context.caller.participant_id)
    receiver = Map.fetch!(context.plan.participants, context.plan.entry_receiver)
    assert {:ok, _snapshot} = Authority.admit(other, receiver.participant_id)

    assert {:ok, foreign} =
             Authority.preview_presence(other, context.candidate.snapshot.present_participant_ids)

    assert foreign.base_snapshot == context.candidate.base_snapshot

    assert {:error, :wrong_policy_authority} =
             SpeechToText.prepare_policy(context.capability, foreign, preparation_options())

    refute_receive {:test_stt_transport_started, _, _}
  end

  test "a blocked replacement constructor leaves the capability responsive and is cancelled" do
    observer = self()
    calls = :atomics.new(1, [])

    before_connect = fn ->
      if :atomics.add_get(calls, 1, 1) == 2 do
        send(observer, {:replacement_connecting, self()})

        receive do
          :continue -> :ok
        end
      end
    end

    context = preparation_room(transport_options: [before_connect: before_connect])
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(
               context.capability,
               context.candidate,
               preparation_options()
             )

    assert_receive {:replacement_connecting, connector}
    monitor = Process.monitor(connector)
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:ok, _resource, :preparing} = SpeechToText.readiness_binding(hd(prepared.resources))
    assert :ok = SpeechToText.discard_policy(context.capability, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^connector, _reason}, 1_000
  end

  defp preparation_room(options \\ []) do
    configure_speech_to_text(Keyword.get(options, :transport_options, []))

    plan =
      compile_plan(
        media_policy: %{save_transcripts: true},
        restrictor?: true,
        observer?: true,
        restriction: Keyword.get(options, :restriction, %{save_transcripts: false})
      )

    assert {:ok, room} = CallEngine.start_call(plan)

    on_exit(fn ->
      case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) do
        [{authority, _value}] -> GenServer.stop(authority, :shutdown)
        [] -> :ok
      end
    end)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    restrictor = Map.fetch!(plan.participants, "restrictor")
    connection_id = unique_id("preparation")
    attachment = attach(plan, room, caller, connection_id)
    assert_receive {:test_stt_transport_started, transport, _connection}
    _receiver = attach(plan, room, receiver, unique_id("receiver"))
    assert {:ok, resources} = Ingress.readiness_resources(attachment.media_ingress)
    resource = Enum.find(resources, &(&1.kind == :speech_to_text))
    collector = collect([resource], room.incarnation_id)
    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    authority = Authority.whereis(room.incarnation_id)
    base = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, restrictor.participant_id)
             )

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 10, :second)
             )

    %{
      plan: plan,
      room: room,
      caller: caller,
      connection_id: connection_id,
      attachment: attachment,
      capability: resource.instance,
      transport: transport,
      candidate: candidate,
      authority: authority,
      join: join
    }
  end

  defp preparation_options,
    do: [
      owner: self(),
      attempt_id: "policy-preparation",
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

  defp preparation_frame(context, sequence),
    do: audio_frame(context.plan, context.room, context.caller, context.connection_id, sequence)

  defp collect(resources, incarnation) do
    start_supervised!(
      {Collector,
       owner: self(),
       incarnation_id: incarnation,
       attempt_id: "policy-preparation",
       resources: resources,
       deadline_ms: System.monotonic_time(:millisecond) + 5_000},
      id: make_ref()
    )
  end

  defp connected_message,
    do: ~s({"type":"Connected","request_id":"prepared-speech","sequence_id":0})

  test "planned room binds STT to its current media policy before accepting audio" do
    configure_speech_to_text()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    attachment = attach(plan, room, caller, "conn-stt-policy")

    assert_receive {:test_stt_transport_started, transport, _connection}
    assert_receive {:test_stt_transport_closed, ^transport}

    assert :ok =
             CallEngine.push_audio(
               attachment,
               audio_frame(plan, room, caller, "conn-stt-policy", 1)
             )

    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  test "keeps live-only STT running and stops it when no consumer remains" do
    configure_speech_to_text()

    plan =
      compile_plan(
        media_policy: %{
          transcript_routes: %{"caller" => ["receiver"]},
          save_transcripts: false
        },
        restrictor?: true
      )

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    restrictor = Map.fetch!(plan.participants, "restrictor")

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    caller_attachment = attach(plan, room, caller, "conn-live-caller")
    assert_receive {:test_stt_transport_started, transport, _connection}
    refute_receive {:test_stt_transport_closed, ^transport}

    _receiver_attachment = attach(plan, room, receiver, "conn-live-receiver")

    assert :ok =
             CallEngine.push_audio(
               caller_attachment,
               audio_frame(plan, room, caller, "conn-live-caller", 1)
             )

    assert_receive {:test_stt_audio, ^transport, <<1>>}

    TestSpeechToTextTransport.deliver(
      transport,
      turn_message("StartOfTurn", 1, "live only")
    )

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: caller_participant_id,
                      text: "live only",
                      final: false
                    }}

    assert caller_participant_id == caller.participant_id

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _participant} = CallEngine.join_participant(join)
    assert_receive {:test_stt_transport_closed, ^transport}

    assert :ok =
             CallEngine.push_audio(
               caller_attachment,
               audio_frame(plan, room, caller, "conn-live-caller", 2)
             )

    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  defp compile_plan(options \\ []) do
    media_policy =
      Keyword.get(options, :media_policy, %{transcript_routes: %{}, save_transcripts: false})

    participants = %{
      "caller" => human_participant(%{speech_to_text: "plan-stt"}),
      "receiver" => human_participant(%{})
    }

    participants =
      if Keyword.get(options, :observer?, false),
        do: Map.put(participants, "observer", human_participant(%{})),
        else: participants

    participants =
      if Keyword.get(options, :restrictor?, false) do
        Map.put(
          participants,
          "restrictor",
          Map.put(
            human_participant(%{}),
            :while_present,
            Keyword.get(options, :restriction, %{
              transcript_routes: %{},
              save_transcripts: false
            })
          )
        )
      else
        participants
      end

    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      media_policy: media_policy,
      call_variables: %{sections: %{}},
      participants: participants,
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "stt-policy-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "stt-policy-room", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-stt-policy",
               actor_id: "actor-stt-policy",
               call_id: unique_id("call-stt-policy"),
               room_id: unique_id("room-stt-policy")
             )

    registries = %{
      capability_profiles: %{
        "plan-stt" => %{
          kind: :speech_to_text,
          provider: Flux,
          options: %{model: "flux-general-multi", encoding: :opus, sample_rate: 48_000}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp human_participant(capabilities) do
    %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: capabilities
    }
  end

  defp attach(plan, room, participant, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} = CallEngine.attach_connection(command)
    attachment
  end

  defp audio_frame(plan, room, participant, connection_id, sequence_number) do
    %AudioFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: connection_id,
      track_id: "track-stt-policy",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: sequence_number,
      timestamp: sequence_number * 960,
      payload: <<1>>,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp turn_message(event, sequence, transcript) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "request-live-only",
      "sequence_id" => sequence,
      "event" => event,
      "trigger" => "model",
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    })
  end

  defp configure_speech_to_text(transport_options \\ []) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [api_key: "runtime-secret"],
      transport: {TestSpeechToTextTransport, [observer: self()] ++ transport_options},
      media_ingress: [
        maximum_frames: 8,
        maximum_bytes: 1024,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 2
      ]
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_text, speech_to_text)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
