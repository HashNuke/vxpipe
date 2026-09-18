defmodule Vxpipe.CallEngine.RoomMixerPolicyPreparationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler, RoomMixer}
  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.RoomMixer.Subscription

  test "prepares a joining subscription without exposing media or replacing the live mixer" do
    context = start_context()
    %{mixer: mixer, authority: authority, candidate: candidate} = context
    existing = subscription_options(context, context.receiver)
    joining = subscription_options(context, context.joining)
    assert {:ok, live_handle} = RoomMixer.subscribe(mixer, existing)
    assert {:ok, live_route, :ready} = Subscription.readiness(live_handle)
    assert {:ok, live_mixer, :ready} = RoomMixer.readiness(mixer)
    before = RoomMixer.stats(mixer)

    assert {:ok, prepared} =
             RoomMixer.prepare_policy(
               mixer,
               candidate,
               Keyword.put(context.options, :subscriptions, [existing, joining])
             )

    assert RoomMixer.stats(mixer) == before
    assert Authority.snapshot(authority) == candidate.base_snapshot
    assert {:ok, ^live_route, :ready} = Subscription.readiness(live_handle)
    assert {:ok, ^live_mixer, :ready} = RoomMixer.readiness(mixer)
    assert live_route in prepared.resources
    joining_handle = Map.fetch!(prepared.subscriptions, context.joining)
    assert {:error, :unknown_subscription} = Subscription.take(joining_handle, 1)

    joining_resource =
      Enum.find(prepared.resources, &(&1.scope == {:participant, context.joining}))

    mixer_resource = Enum.find(prepared.resources, &(&1.kind == :room_mixer))
    assert mixer_resource.instance == mixer
    assert mixer_resource.generation == live_mixer.generation
    assert {:ok, ^mixer_resource, :ready} = RoomMixer.readiness_binding(mixer_resource)
    assert {:ok, ^joining_resource, :ready} = Subscription.readiness_binding(joining_resource)
    assert {:ok, ^joining_resource, :ready} = Subscription.readiness(joining_handle)

    assert :ok = RoomMixer.push(mixer, frame(context, 1, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert {:ok, [_]} = Subscription.take(live_handle, 1)
    assert {:error, :unknown_subscription} = Subscription.take(joining_handle, 1)
    assert :ok = RoomMixer.push(mixer, frame(context, 2, 2))
    assert {:ok, committed} = Authority.admit(authority, context.joining)
    assert committed == candidate.snapshot
    assert {:ok, ^mixer_resource, :ready} = RoomMixer.readiness_binding(mixer_resource)
    assert {:ok, ^joining_resource, :ready} = Subscription.readiness_binding(joining_resource)
    assert {:ok, ^joining_resource, :ready} = Subscription.readiness(joining_handle)
    assert {:ok, ^live_route, :ready} = Subscription.readiness(live_handle)
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 2)
    assert {:ok, []} = Subscription.take(joining_handle, 1)
    assert :ok = RoomMixer.push(mixer, frame(context, 3, 4))
    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 4)
    assert {:ok, [received]} = Subscription.take(joining_handle, 1)
    assert received.timestamp == 4
    assert received.source_participant_ids == [context.caller]
    assert {:error, :stale_preparation} = RoomMixer.discard_policy(mixer, prepared.token)
  end

  test "ordinary subscription registration cannot replace a prepared queue" do
    context = start_context()
    options = subscription_options(context, context.receiver)

    assert {:ok, prepared} =
             RoomMixer.prepare_policy(
               context.mixer,
               context.candidate,
               Keyword.put(context.options, :subscriptions, [options])
             )

    assert {:error, :preparation_conflict} = RoomMixer.subscribe(context.mixer, options)
    assert {:ok, _} = Authority.admit(context.authority, context.joining)
    handle = Map.fetch!(prepared.subscriptions, context.receiver)
    assert {:ok, []} = Subscription.take(handle, 1)
  end

  test "discarding prepared subscriptions preserves queued source audio" do
    context = start_context()
    existing = subscription_options(context, context.receiver)
    assert {:ok, live} = RoomMixer.subscribe(context.mixer, existing)
    assert :ok = RoomMixer.push(context.mixer, frame(context, 1, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(context.mixer, 0)

    options =
      Keyword.put(context.options, :subscriptions, [
        subscription_options(context, context.joining)
      ])

    assert {:ok, prepared} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
    assert :ok = RoomMixer.discard_policy(context.mixer, prepared.token)
    [mixer_resource, route] = prepared.resources
    assert {:error, :unavailable} = RoomMixer.readiness_binding(mixer_resource)
    assert {:error, :unavailable} = Subscription.readiness_binding(route)
    assert {:ok, [received]} = Subscription.take(live, 1)
    assert received.timestamp == 0
    assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
    assert {:ok, next} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
    refute next.token == prepared.token
    assert {:error, :stale_preparation} = RoomMixer.discard_policy(context.mixer, prepared.token)
    assert :ok = RoomMixer.discard_policy(context.mixer, next.token)
  end

  test "refreshing unrelated membership retains the subscription and its original deadline" do
    context = start_context()
    phase = start_supervised!({Agent, fn -> :phase end}, id: :phase)

    options =
      context.options
      |> Keyword.put(:owner, phase)
      |> Keyword.put(:subscriptions, [subscription_options(context, context.joining)])

    assert {:ok, prepared} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
    assert {:ok, ^prepared} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)

    assert {:error, :preparation_conflict} =
             RoomMixer.prepare_policy(
               context.mixer,
               context.candidate,
               Keyword.update!(options, :deadline_ms, &(&1 + 1_000))
             )

    assert {:ok, current} = Authority.admit(context.authority, context.observer)
    assert {:error, :unavailable} = RoomMixer.readiness_binding(hd(prepared.resources))

    assert {:error, :stale_candidate} =
             RoomMixer.prepare_policy(context.mixer, context.candidate, options)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(current.present_participant_ids, context.joining)
             )

    assert {:ok, refreshed} = RoomMixer.prepare_policy(context.mixer, candidate, options)
    assert refreshed.token == prepared.token
    assert refreshed.subscriptions == prepared.subscriptions
    [old_mixer, old_subscription] = prepared.resources
    [mixer, subscription] = refreshed.resources
    assert mixer.generation == old_mixer.generation
    assert subscription.generation == old_subscription.generation
    assert subscription.configuration == old_subscription.configuration
    collector = collect(context, refreshed.resources)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert {:ok, committed} = Authority.admit(context.authority, context.joining)
    assert committed == candidate.snapshot
    stop_supervised!(:phase)
    assert {:ok, ^mixer, :ready} = RoomMixer.readiness_binding(mixer)
    assert {:ok, ^subscription, :ready} = Subscription.readiness_binding(subscription)
  end

  for failure <- [:expiry, :phase_owner, :subscriber] do
    @failure failure
    test "#{failure} invalidates prepared subscriptions without losing the live route" do
      context = start_context()

      phase =
        if @failure == :phase_owner,
          do: start_supervised!({Agent, fn -> :phase end}, id: :phase),
          else: self()

      subscriber =
        if @failure == :subscriber,
          do: start_supervised!({Agent, fn -> :destination end}, id: :destination),
          else: self()

      assert {:ok, live} =
               RoomMixer.subscribe(context.mixer, subscription_options(context, context.receiver))

      assert {:ok, live_resource, :ready} = Subscription.readiness(live)

      joining =
        Keyword.put(subscription_options(context, context.joining), :subscriber, subscriber)

      options =
        context.options |> Keyword.put(:owner, phase) |> Keyword.put(:subscriptions, [joining])

      options =
        if @failure == :expiry,
          do: Keyword.put(options, :deadline_ms, System.monotonic_time(:millisecond) + 250),
          else: options

      assert {:ok, prepared} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
      collector = collect(context, prepared.resources)
      assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

      case @failure do
        :phase_owner -> stop_supervised!(:phase)
        :subscriber -> stop_supervised!(:destination)
        :expiry -> :ok
      end

      mixer = context.mixer
      token = prepared.token

      if @failure == :phase_owner do
        handle = Map.fetch!(prepared.subscriptions, context.joining)
        id = handle.id
        route_token = handle.token
        assert_receive {:vxpipe_room_subscription_cancelled, ^mixer, ^id, ^route_token}, 1_000
      else
        assert_receive {:vxpipe_mixer_policy_failed, ^mixer, ^token}, 1_000
      end

      assert :ok = Collector.refresh(collector)

      assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000

      assert {:error, :policy_not_ready} =
               Enforcer.apply(context.mixer, context.candidate.snapshot, 1_000)

      assert {:ok, ^live_resource, :ready} = Subscription.readiness(live)
      assert :ok = RoomMixer.push(context.mixer, frame(context, 1, 0))
      assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(context.mixer, 0)
      assert {:ok, [_]} = Subscription.take(live, 1)

      if @failure == :phase_owner do
        assert {:error, :preparation_conflict} =
                 RoomMixer.prepare_policy(context.mixer, context.candidate, options)
      else
        assert :ok = RoomMixer.discard_policy(context.mixer, prepared.token)
      end

      options =
        Keyword.put(context.options, :subscriptions, [
          subscription_options(context, context.joining)
        ])

      assert {:ok, next} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
      refute next.token == prepared.token
      send(context.mixer, {:mixer_policy_expired, prepared.token})

      assert {:error, :stale_preparation} =
               RoomMixer.discard_policy(context.mixer, prepared.token)

      assert {:ok, _, :ready} = RoomMixer.readiness_binding(hd(next.resources))
      assert :ok = RoomMixer.discard_policy(context.mixer, next.token)
    end
  end

  for live? <- [true, false] do
    test "reconciles a departed #{if live?, do: "live", else: "private"} subscription without replacing its peers" do
      context = start_context()
      subscriber = start_supervised!({Agent, fn -> :listener end}, id: :departing_listener)

      departing =
        Keyword.put(subscription_options(context, context.receiver), :subscriber, subscriber)

      retained = subscription_options(context, context.joining)
      if unquote(live?), do: assert({:ok, _} = RoomMixer.subscribe(context.mixer, departing))
      options = Keyword.put(context.options, :subscriptions, [departing, retained])
      assert {:ok, prepared} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
      handle = Map.fetch!(prepared.subscriptions, context.joining)
      assert {:ok, resource, :ready} = Subscription.readiness(handle)
      mixer = context.mixer
      token = prepared.token

      stop_supervised!(:departing_listener)
      assert_receive {:vxpipe_mixer_policy_failed, ^mixer, ^token}

      assert {:error, :policy_not_ready} =
               Enforcer.apply(mixer, context.candidate.snapshot, 1_000)

      assert {:error, :subscriber_unavailable} =
               RoomMixer.prepare_policy(mixer, context.candidate, options)

      assert {:ok, refreshed} =
               RoomMixer.prepare_policy(
                 mixer,
                 context.candidate,
                 Keyword.put(options, :subscriptions, [retained])
               )

      assert refreshed.token == token
      assert refreshed.subscriptions == %{context.joining => handle}
      assert {:ok, ^resource, :ready} = Subscription.readiness(handle)
      refute_receive {:vxpipe_room_subscription_cancelled, ^mixer, _, _}, 0
      assert {:ok, _} = Authority.admit(context.authority, context.joining)
      assert :ok = RoomMixer.push(mixer, frame(context, 1, 0))
      assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
      assert {:ok, [_]} = Subscription.take(handle, 1)
    end
  end

  test "a changed output policy retains the subscription and applies privacy only at commit" do
    context = start_context(%{audio_routes: %{}})
    options = subscription_options(context, context.receiver)
    assert {:ok, live} = RoomMixer.subscribe(context.mixer, options)
    assert {:ok, previous, :ready} = Subscription.readiness(live)
    assert :ok = RoomMixer.push(context.mixer, frame(context, 1, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(context.mixer, 0)

    assert {:ok, prepared} =
             RoomMixer.prepare_policy(
               context.mixer,
               context.candidate,
               Keyword.put(context.options, :subscriptions, [options])
             )

    handle = Map.fetch!(prepared.subscriptions, context.receiver)
    assert {:ok, future, :ready} = Subscription.readiness(handle)
    assert future.generation == previous.generation
    assert future.configuration == previous.configuration
    refute future.policy_interval == previous.policy_interval
    assert {:ok, ^previous, :ready} = Subscription.readiness(live)
    assert {:ok, [_]} = Subscription.take(live, 1)
    assert :ok = RoomMixer.push(context.mixer, frame(context, 2, 2))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(context.mixer, 2)
    assert {:ok, _} = Authority.admit(context.authority, context.joining)
    assert {:ok, ^future, :ready} = Subscription.readiness(handle)
    assert {:ok, []} = Subscription.take(live, 1)
    assert :ok = RoomMixer.push(context.mixer, frame(context, 3, 4))
    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(context.mixer, 4)
    assert RoomMixer.stats(context.mixer).subscriptions == 1
  end

  test "foreign candidates and invalid subscription sets cannot reserve room resources" do
    context = start_context()
    foreign = start_context()
    before = RoomMixer.stats(context.mixer)

    assert {:error, :stale_candidate} =
             RoomMixer.prepare_policy(context.mixer, foreign.candidate, context.options)

    valid = subscription_options(context, context.joining)

    invalid =
      subscription_options(context, context.receiver) |> Keyword.put(:tenant_id, "foreign")

    assert {:error, :wrong_room} =
             RoomMixer.prepare_policy(
               context.mixer,
               context.candidate,
               Keyword.put(context.options, :subscriptions, [valid, invalid])
             )

    assert RoomMixer.stats(context.mixer) == before

    assert {:ok, prepared} =
             RoomMixer.prepare_policy(
               context.mixer,
               context.candidate,
               Keyword.put(context.options, :subscriptions, [valid])
             )

    assert :ok = RoomMixer.discard_policy(context.mixer, prepared.token)
    assert RoomMixer.stats(context.mixer) == before
  end

  test "a later preparation retains an adopted subscription handle when its policy is unchanged" do
    context = start_context()
    subscription = subscription_options(context, context.joining)
    options = Keyword.put(context.options, :subscriptions, [subscription])
    assert {:ok, first} = RoomMixer.prepare_policy(context.mixer, context.candidate, options)
    assert {:ok, current} = Authority.admit(context.authority, context.joining)
    handle = Map.fetch!(first.subscriptions, context.joining)
    assert {:ok, resource, :ready} = Subscription.readiness(handle)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(current.present_participant_ids, context.observer)
             )

    options = Keyword.put(options, :attempt_id, "next-attempt")
    assert {:ok, next} = RoomMixer.prepare_policy(context.mixer, candidate, options)
    assert Map.fetch!(next.subscriptions, context.joining) == handle
    assert resource in next.resources
    assert {:ok, _} = Authority.admit(context.authority, context.observer)
    assert {:ok, ^resource, :ready} = Subscription.readiness(handle)
    assert :ok = RoomMixer.push(context.mixer, frame(context, 1, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(context.mixer, 0)
    assert {:ok, [_]} = Subscription.take(handle, 1)
  end

  test "removing one prospective listener cancels only its new queue" do
    context = start_context()
    present = context.candidate.snapshot.present_participant_ids |> MapSet.put(context.observer)
    assert {:ok, both} = Authority.preview_presence(context.authority, present)
    joining_options = subscription_options(context, context.joining)
    observer_options = subscription_options(context, context.observer)

    assert {:ok, first} =
             RoomMixer.prepare_policy(
               context.mixer,
               both,
               Keyword.put(context.options, :subscriptions, [joining_options, observer_options])
             )

    joining = Map.fetch!(first.subscriptions, context.joining)
    removed = Map.fetch!(first.subscriptions, context.observer)
    assert {:ok, joining_resource, :ready} = Subscription.readiness(joining)

    assert {:ok, next} =
             RoomMixer.prepare_policy(
               context.mixer,
               context.candidate,
               Keyword.put(context.options, :subscriptions, [joining_options])
             )

    assert next.token == first.token
    assert next.subscriptions == %{context.joining => joining}
    assert {:ok, ^joining_resource, :ready} = Subscription.readiness(joining)
    assert {:error, :unavailable} = Subscription.readiness(removed)
    mixer = context.mixer
    removed_id = removed.id
    removed_token = removed.token
    assert_receive {:vxpipe_room_subscription_cancelled, ^mixer, ^removed_id, ^removed_token}
    assert {:ok, _} = Authority.admit(context.authority, context.joining)
    assert {:ok, ^joining_resource, :ready} = Subscription.readiness(joining)
  end

  defp start_context(joining_policy \\ %{}) do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "mixer-preparation-#{suffix}"

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "transfer"}
    }

    participants = Map.new(["caller", "receiver", "joining", "observer"], &{&1, human})
    participants = put_in(participants["joining"][:while_present], joining_policy)

    assert {:ok, call_spec} =
             CallSpec.new(
               %{
                 schema_version: CallSpec.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "receiver",
                 defaults: %{capabilities: %{}},
                 call_variables: %{sections: %{}},
                 participants: participants,
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "mixer-preparation",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "mixer-preparation", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-mixer",
               actor_id: "actor-mixer",
               call_id: "call-#{suffix}",
               room_id: "room-#{suffix}"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{
               host_tools: %{}
             })

    authority =
      start_supervised!(
        Supervisor.child_spec({Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        )
      )

    identities =
      Map.new([:caller, :receiver, :joining, :observer], fn key ->
        {key, Map.fetch!(plan.participants, Atom.to_string(key)).participant_id}
      end)

    assert {:ok, _} = Authority.admit(authority, identities.caller)
    assert {:ok, base} = Authority.admit(authority, identities.receiver)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, identities.joining)
             )

    identity = %{tenant_id: plan.tenant_id, room_id: plan.room_id, incarnation_id: incarnation}

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(identity) ++
           [
             sample_rate: 8_000,
             channels: 1,
             frame_samples: 2,
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 4
           ]}
      )

    assert {:ok, ^base} = Authority.register_enforcer(authority, mixer)

    Map.merge(identities, %{
      mixer: mixer,
      authority: authority,
      candidate: candidate,
      identity: identity,
      options: [
        owner: self(),
        attempt_id: "mixer-policy",
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    })
  end

  defp subscription_options(context, participant),
    do:
      Map.to_list(context.identity) ++
        [
          id: participant,
          recipient_participant_id: participant,
          mode: :mix_minus,
          subscriber: self()
        ]

  defp collect(context, resources),
    do:
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: context.identity.incarnation_id,
         attempt_id: "mixer-collection",
         resources: resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

  defp frame(context, sequence, timestamp) do
    snapshot = Authority.snapshot(context.authority)

    struct!(
      NormalizedFrame,
      Map.merge(context.identity, %{
        source_participant_id: context.caller,
        connection_id: "caller-connection",
        track_id: "caller-track",
        sequence_number: sequence,
        timestamp: timestamp,
        policy_revision: Snapshot.interval(snapshot, :audio_input, context.caller),
        sample_rate: 8_000,
        channels: 1,
        payload: <<1::little-signed-16, 2::little-signed-16>>
      })
    )
  end
end
