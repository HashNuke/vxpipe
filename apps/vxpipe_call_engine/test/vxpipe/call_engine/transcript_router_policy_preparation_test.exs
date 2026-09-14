defmodule Vxpipe.CallEngine.TranscriptRouterPolicyPreparationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, TranscriptRouter}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer}
  alias Vxpipe.CallEngine.Readiness.Collector

  test "refresh retains the router and lease while current transcript permissions remain installed" do
    context = start_context()
    phase = start_supervised!({Agent, fn -> :phase end})
    options = Keyword.put(context.options, :owner, phase)
    assert {:ok, live, :ready} = TranscriptRouter.readiness(context.router)

    assert {:ok, prepared} =
             TranscriptRouter.prepare_policy(context.router, context.candidate, options)

    assert {:ok, ^prepared} =
             TranscriptRouter.prepare_policy(context.router, context.candidate, options)

    assert {:ok, ^live, :ready} = TranscriptRouter.readiness(context.router)
    assert_allowed(context)

    assert {:error, :preparation_conflict} =
             TranscriptRouter.prepare_policy(
               context.router,
               context.candidate,
               Keyword.update!(options, :deadline_ms, &(&1 + 1_000))
             )

    assert {:ok, current} = Authority.admit(context.authority, context.observer)
    assert {:error, :unavailable} = TranscriptRouter.readiness_binding(hd(prepared.resources))

    assert {:error, :stale_candidate} =
             TranscriptRouter.prepare_policy(context.router, context.candidate, options)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(current.present_participant_ids, context.joining)
             )

    assert {:ok, refreshed} = TranscriptRouter.prepare_policy(context.router, candidate, options)
    assert refreshed.token == prepared.token
    assert [resource] = refreshed.resources
    assert resource.instance == live.instance
    assert resource.generation == live.generation
    assert resource.configuration == live.configuration
    assert {:ok, ^resource, :ready} = TranscriptRouter.readiness_binding(resource)
    assert_allowed(context)
    assert {:ok, installed} = Authority.admit(context.authority, context.joining)
    assert installed == candidate.snapshot
    stop_supervised!(Agent)
    assert {:ok, ^resource, :ready} = TranscriptRouter.readiness_binding(resource)

    assert {:error, :stale_preparation} =
             TranscriptRouter.discard_policy(context.router, prepared.token)

    assert {:ok, decision} =
             TranscriptRouter.project_current(context.router, context.caller, context.recipients)

    assert decision.recipient_participant_ids == MapSet.new()
  end

  test "discarding a candidate preserves current projections and allows a fresh lease" do
    context = start_context()
    assert {:ok, live, :ready} = TranscriptRouter.readiness(context.router)

    assert {:ok, prepared} =
             TranscriptRouter.prepare_policy(context.router, context.candidate, context.options)

    assert :ok = TranscriptRouter.discard_policy(context.router, prepared.token)
    assert {:error, :unavailable} = TranscriptRouter.readiness_binding(hd(prepared.resources))
    assert {:ok, ^live, :ready} = TranscriptRouter.readiness(context.router)
    assert_allowed(context)

    assert {:ok, retry} =
             TranscriptRouter.prepare_policy(context.router, context.candidate, context.options)

    refute retry.token == prepared.token

    assert {:error, :stale_preparation} =
             TranscriptRouter.discard_policy(context.router, prepared.token)

    assert {:ok, resource, :ready} = TranscriptRouter.readiness_binding(hd(retry.resources))
    assert resource in retry.resources
  end

  for failure <- [:owner_loss, :deadline] do
    @failure failure
    test "#{failure} prevents prepared policy adoption without changing live transcript permissions" do
      context = start_context()
      phase = start_supervised!({Agent, fn -> :phase end})

      options =
        case @failure do
          :owner_loss ->
            Keyword.put(context.options, :owner, phase)

          :deadline ->
            Keyword.put(context.options, :deadline_ms, System.monotonic_time(:millisecond) + 200)
        end

      assert {:ok, live, :ready} = TranscriptRouter.readiness(context.router)

      assert {:ok, prepared} =
               TranscriptRouter.prepare_policy(context.router, context.candidate, options)

      [resource] = prepared.resources

      case @failure do
        :owner_loss ->
          collector =
            start_supervised!(
              {Collector,
               owner: self(),
               incarnation_id: resource.binding |> elem(0),
               attempt_id: "owner-failure",
               resources: [resource],
               deadline_ms: Keyword.fetch!(context.options, :deadline_ms)}
            )

          assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
          stop_supervised!(Agent)
          Collector.refresh(collector)
          assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000

        :deadline ->
          router = context.router
          token = prepared.token
          assert_receive {:vxpipe_transcript_policy_failed, ^router, ^token}, 1_000
      end

      assert {:ok, ^resource, :failed} = TranscriptRouter.readiness_binding(resource)

      assert {:error, :policy_not_ready} =
               Enforcer.apply(context.router, context.candidate.snapshot, 1_000)

      assert {:ok, ^live, :ready} = TranscriptRouter.readiness(context.router)
      assert_allowed(context)
      assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
      assert :ok = TranscriptRouter.discard_policy(context.router, prepared.token)
    end
  end

  defp assert_allowed(context) do
    assert {:ok, decision} =
             TranscriptRouter.project_current(context.router, context.caller, context.recipients)

    assert decision.recipient_participant_ids == context.recipients
  end

  defp start_context do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "transcript-preparation-#{suffix}"

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "transfer"}
    }

    participants = Map.new(["caller", "receiver", "joining", "observer"], &{&1, human})

    participants =
      put_in(participants["joining"][:while_present], %{
        transcript_routes: %{},
        save_transcripts: false
      })

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "receiver",
                 defaults: %{capabilities: %{}},
                 participants: participants,
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "transcript-preparation",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "transcript-preparation", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-transcript",
               actor_id: "actor-transcript",
               call_id: "call-#{suffix}",
               room_id: "room-#{suffix}"
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{},
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

    router =
      start_supervised!(
        {TranscriptRouter,
         tenant_id: plan.tenant_id,
         room_id: plan.room_id,
         incarnation_id: incarnation,
         maximum_retained_revisions: 8}
      )

    assert {:ok, _initial} = Authority.register_enforcer(authority, router)
    assert {:ok, _} = Authority.admit(authority, identities.caller)
    assert {:ok, base} = Authority.admit(authority, identities.receiver)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, identities.joining)
             )

    Map.merge(identities, %{
      router: router,
      authority: authority,
      candidate: candidate,
      recipients: MapSet.new([identities.receiver]),
      options: [
        owner: self(),
        attempt_id: "transcript-policy",
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    })
  end
end
