defmodule Vxpipe.CallEngine.Capability.SpeechToTextDiagnosticsTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Speech.CapabilityTree
  alias Vxpipe.CallEngine.SpeechSessionProbe
  @projection __MODULE__.Projection

  setup do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: @projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :loaded)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(@projection)
    :ok
  end

  test "only a current observation handle accompanies completion to the owning room" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)
    reference = make_ref()
    assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: reference]})
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started}}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: reference, text: "", endpointing: :provider_gap]}
             )

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{
                      kind: :turn_ended,
                      allocation_generation: ^generation,
                      turn_ref: ^reference
                    }, ^handoff}

    CaptureHandoff.close(handoff)
    next = make_ref()
    assert :ok = GenServer.call(provider, {:emit, :speech_started, [turn_ref: next]})
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :turn_started}}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: next, text: "", endpointing: :provider_gap]}
             )

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :turn_ended, turn_ref: ^next}}
  end

  test "accepted PCM reaches its exact source tap without changing provider admission" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability, maximum_count: 1)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, {:audio, copied}, charge} = CaptureHandoff.message(handoff, message)
    assert copied == frame
    # Keep the first item reserved: a full observer must not change call input.
    assert :ok = SpeechToText.push_audio(capability, %{frame | sequence_number: 2})
    assert_receive {:probe_input, _}
    assert %{pending_count: 1, overflow: 1} = CaptureHandoff.stats(handoff)
    :ok = CaptureHandoff.release(handoff, charge, :processed)
  end

  test "repeated attachment is idempotent and stale allocation requests preserve the current tap" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = attach(capability, generation, frame, handoff)
    assert {:error, :unavailable} = attach(capability, make_ref(), frame, handoff)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = queued
    assert {:ok, {:audio, ^frame}, charge} = CaptureHandoff.message(handoff, queued)
    :ok = CaptureHandoff.release(handoff, charge, :processed)
  end

  for permission <- [:record_audio, :save_transcripts] do
    @permission permission
    test "changing #{@permission} fences installed observation and pending discovery" do
      {capability, generation, frame} = capability(:ok)
      installed = handoff(capability)
      assert :ok = attach(capability, generation, frame, installed)
      probe = handoff(capability)
      assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
      changed = policy(1, ["human"])
      changed = %{changed | effective: Map.put(changed.effective, @permission, false)}
      assert :ok = Enforcer.apply(capability, changed, 1_000)
      refute CaptureHandoff.current?(installed)

      if @permission == :save_transcripts do
        assert_receive {:probe_initializing, _, _}
        assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
      end

      assert :ok = SpeechToText.push_audio(capability, frame)
      assert_receive {:probe_input, _}
      refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    end
  end

  test "legacy snapshots without scoped intervals remain fenced by global revision" do
    alias Vxpipe.CallEngine.Capability.SpeechToText.State
    alias Vxpipe.CallEngine.Diagnostics.AudioTap
    generation = make_ref()
    observer = handoff(self())
    source = %{track_id: "legacy", source_epoch: make_ref()}
    state = struct(State, policy: policy(0, ["human"]), identity: %{participant_id: "human"})

    assert {:ok, tap} =
             AudioTap.new(observer, generation, State.diagnostic_intervals(state), source)

    changed = %{state | policy: policy(1, ["human", "another"])}
    AudioTap.policy_change(tap, State.diagnostic_intervals(changed))
    refute CaptureHandoff.current?(observer)
  end

  test "unrelated room presence changes preserve accepted-source observation" do
    {:ok, initial} = Snapshot.prepare(policy(0, ["human"]), nil)
    {capability, generation, frame} = capability(:ok, initial_policy: initial)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = Enforcer.apply(capability, policy(1, ["human", "another"]), 1_000)
    assert {:ok, %{allocation_generation: ^generation}} = SpeechToText.input_binding(capability)
    assert CaptureHandoff.current?(handoff)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, {:audio, ^frame}, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
  end

  test "discovery proof survives unrelated revisions before and after source announcement" do
    {:ok, initial} = Snapshot.prepare(policy(0, ["human"]), nil)
    {capability, generation, frame} = capability(:ok, initial_policy: initial)
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
    assert :ok = Enforcer.apply(capability, policy(1, ["human", "another"]), 1_000)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, packet, _} = message
    assert {:source_ready, ^generation, fence, track, epoch, _, _, _, _} = packet
    assert {:ok, ^packet, charge} = CaptureHandoff.message(probe, message)
    CaptureHandoff.release(probe, charge, :processed)
    assert :ok = Enforcer.apply(capability, policy(2, ["human", "another", "third"]), 1_000)
    output = handoff(capability)

    assert :ok =
             SpeechToText.attach_diagnostics(
               capability,
               generation,
               fence,
               %{track_id: track, source_epoch: epoch},
               output,
               probe.token
             )

    assert :ok = SpeechToText.push_audio(capability, %{frame | sequence_number: 2})
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = observed
    assert {:ok, {:audio, _}, charge} = CaptureHandoff.message(output, observed)
    CaptureHandoff.release(output, charge, :processed)
  end

  test "reapplying the same installed policy does not retire its tap" do
    {capability, generation, frame} = capability(:ok)
    installed = policy(1, ["human"])
    assert :ok = Enforcer.apply(capability, installed, 1_000)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert {:error, :stale_policy_revision} = Enforcer.apply(capability, installed, 1_000)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = queued
    assert {:ok, {:audio, ^frame}, charge} = CaptureHandoff.message(handoff, queued)
    :ok = CaptureHandoff.release(handoff, charge, :processed)
  end

  test "missing observation metadata cannot fail otherwise accepted input" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = SpeechToText.push_audio(capability, Map.delete(frame, :source_epoch))
    assert_receive {:probe_input, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "provider rejected input is never observed" do
    {capability, generation, frame} = capability({:error, :busy})
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert {:error, :unavailable} = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert %{pending_count: 0} = CaptureHandoff.stats(handoff)
  end

  test "a source replacement retires the old tap without rejecting accepted audio" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = SpeechToText.push_audio(capability, %{frame | source_epoch: make_ref()})
    assert_receive {:probe_input, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    refute CaptureHandoff.current?(handoff)
    assert :ok = SpeechToText.push_audio(capability, frame)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "policy transition revokes already queued audio and stale allocation attachment" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = queued
    assert :ok = Enforcer.apply(capability, policy(1, []), 1_000)
    assert {:error, :revoked} = CaptureHandoff.message(handoff, queued)
    assert {:error, :unavailable} = attach(capability, generation, frame, handoff(capability))
    assert {:error, :policy_denied} = SpeechToText.push_audio(capability, frame)
  end

  test "capability death revokes queued evidence without relying on terminate cleanup" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = queued
    monitor = Process.monitor(capability)
    Process.exit(capability, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^capability, :killed}
    assert {:error, :revoked} = CaptureHandoff.message(handoff, queued)
  end

  test "rejected policy update preserves active observation" do
    {capability, generation, frame} = capability(:ok)
    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)

    assert {:error, :unexpected_policy_revision} =
             Enforcer.apply(capability, policy(2, ["human"]), 1_000)

    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "discarded preparation preserves active observation" do
    alias Vxpipe.CallEngine.ResolvedCallPlan
    alias Vxpipe.CallEngine.ResolvedCallPlan.{MediaPolicy, Participant}
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    incarnation = "tap-review-#{System.unique_integer([:positive])}"

    participants = %{
      "human" =>
        struct(Participant, participant_id: "human", while_present: MediaPolicy.inherit()),
      "restrictor" =>
        struct(Participant,
          participant_id: "restrictor",
          while_present: %{MediaPolicy.inherit() | transcript_routes: %{}}
        )
    }

    plan =
      struct(ResolvedCallPlan, media_policy: MediaPolicy.inherit(), participants: participants)

    authority =
      start_supervised!(
        Supervisor.child_spec({Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        )
      )

    assert {:ok, base} = Authority.admit(authority, "human")

    {capability, generation, frame} =
      capability(:ok, initial_policy: base, incarnation_id: incarnation)

    handoff = handoff(capability)
    assert :ok = attach(capability, generation, frame, handoff)
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, "restrictor")
             )

    assert {:ok, %{change: :replace, token: token}} =
             SpeechToText.prepare_policy(capability, candidate,
               owner: self(),
               attempt_id: "discard-review",
               deadline_ms: System.monotonic_time(:millisecond) + 5_000
             )

    assert_receive {:probe_initializing, _, _}
    assert :ok = SpeechToText.discard_policy(capability, token)
    assert {:ok, %{allocation_generation: ^generation}} = SpeechToText.input_binding(capability)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:audio, _}, _}
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:source_ready, _, _, _, _, _, _, _, _}, _}
  end

  test "source discovery reports only the next accepted frame without retaining audio" do
    {capability, generation, frame} = capability(:ok)
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
    assert_receive {:vxpipe_diagnostic_capture, _, _, packet, _} = message

    assert {:source_ready, ^generation, {0, 0}, track, epoch, :linear16, 16_000, 1,
            :benchmark_only} =
             packet

    assert track == frame.track_id and epoch == frame.source_epoch
    assert {:ok, ^packet, charge} = CaptureHandoff.message(probe, message)
    CaptureHandoff.release(probe, charge, :processed)
    assert :ok = SpeechToText.push_audio(capability, %{frame | sequence_number: 2})
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "discovery excludes rejected audio independently of response agents" do
    {capability, _generation, frame} = capability({:error, :busy})
    probe = handoff(capability)

    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
    assert {:error, :unavailable} = SpeechToText.push_audio(capability, frame)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "revoked and policy-stale discovery cannot emit a source" do
    {capability, _generation, frame} = capability(:ok)
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
    CaptureHandoff.close(probe)
    assert :ok = SpeechToText.push_audio(capability, frame)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    next = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, next)
    changed = put_in(policy(1, ["human"]).effective.record_audio, false)
    assert :ok = Enforcer.apply(capability, changed, 1_000)
    assert :ok = SpeechToText.push_audio(capability, frame)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "discovery has one pending slot and expired requests cannot affect replacements" do
    {capability, _generation, frame} = capability(:ok)
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
    token = :sys.get_state(capability).diagnostic_probe.token

    assert {:error, :unavailable} =
             SpeechToText.discover_input_diagnostics(capability, handoff(capability))

    send(capability, {:diagnostic_probe_expired, token})
    assert :sys.get_state(capability).diagnostic_probe == nil
    refute CaptureHandoff.current?(probe)
    next = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, next)
    send(capability, {:diagnostic_probe_expired, token})
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:source_ready, _, _, _, _, _, _, _, _}, _}
    assert CaptureHandoff.current?(next)
  end

  test "a delayed expiry message cannot let an expired request observe accepted audio" do
    {capability, _generation, frame} = capability(:ok)
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)

    :sys.replace_state(capability, fn state ->
      %{
        state
        | diagnostic_probe: %{
            state.diagnostic_probe
            | deadline: System.monotonic_time(:millisecond) - 1
          }
      }
    end)

    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    refute CaptureHandoff.current?(probe)
  end

  test "prepared policy adoption does not resurrect a consumed discovery slot" do
    alias Vxpipe.CallEngine.ResolvedCallPlan
    alias Vxpipe.CallEngine.ResolvedCallPlan.{MediaPolicy, Participant}
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    incarnation = "discovery-review-#{System.unique_integer([:positive])}"

    participants = %{
      "human" =>
        struct(Participant, participant_id: "human", while_present: MediaPolicy.inherit()),
      "restrictor" =>
        struct(Participant,
          participant_id: "restrictor",
          while_present: %{MediaPolicy.inherit() | transcript_routes: %{}}
        )
    }

    plan =
      struct(ResolvedCallPlan, media_policy: MediaPolicy.inherit(), participants: participants)

    authority =
      start_supervised!(
        Supervisor.child_spec(
          {Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        )
      )

    assert {:ok, base} = Authority.admit(authority, "human")

    {capability, _generation, frame} =
      capability(:ok, initial_policy: base, incarnation_id: incarnation)

    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, "restrictor")
             )

    assert {:ok, %{change: :replace, resources: [resource]}} =
             SpeechToText.prepare_policy(capability, candidate,
               owner: self(),
               attempt_id: "review",
               deadline_ms: System.monotonic_time(:millisecond) + 5_000
             )

    assert_receive {:probe_initializing, _, _}
    await_prepared_connection(resource)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:source_ready, _, _, _, _, _, _, _, _}, _}
    assert :sys.get_state(capability).diagnostic_probe == nil
    assert :ok = Enforcer.apply(capability, candidate.snapshot, 1_000)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, handoff(capability))
  end

  defp await_prepared_connection(resource) do
    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Vxpipe.CallEngine.Readiness.Collector,
           owner: self(),
           incarnation_id: "prepared-stt-test",
           attempt_id: "prepared-stt-ready",
           resources: [resource],
           deadline_ms: System.monotonic_time(:millisecond) + 1_000},
          id: {:prepared_stt_collector, resource.generation}
        )
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    stop_supervised!({:prepared_stt_collector, resource.generation})
  end

  test "retirement timeout does not strand a canceled discovery slot" do
    alias Vxpipe.CallEngine.ResolvedCallPlan
    alias Vxpipe.CallEngine.ResolvedCallPlan.{MediaPolicy, Participant}
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    incarnation = "discovery-retire-review-#{System.unique_integer([:positive])}"

    participants = %{
      "human" =>
        struct(Participant, participant_id: "human", while_present: MediaPolicy.inherit()),
      "restrictor" =>
        struct(Participant,
          participant_id: "restrictor",
          while_present: %{MediaPolicy.inherit() | transcript_routes: %{}}
        )
    }

    plan =
      struct(ResolvedCallPlan, media_policy: MediaPolicy.inherit(), participants: participants)

    authority =
      start_supervised!(
        Supervisor.child_spec(
          {Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        )
      )

    assert {:ok, base} = Authority.admit(authority, "human")

    {capability, generation, _frame} =
      capability(:ok, initial_policy: base, incarnation_id: incarnation)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, "restrictor")
             )

    assert {:ok, %{change: :replace, resources: [resource]}} =
             SpeechToText.prepare_policy(capability, candidate,
               owner: self(),
               attempt_id: "retire-review",
               deadline_ms: System.monotonic_time(:millisecond) + 500
             )

    assert_receive {:probe_initializing, _, _}
    await_prepared_connection(resource)
    state = :sys.get_state(capability)
    control = state.scope.control
    parent = self()

    hook = fn debug_state, event, _process_state ->
      case event do
        {:in, {:"$gen_call", _from, {:close, %{generation: ^generation}, _reason, _deadline}}} ->
          send(parent, :retirement_blocked)

          receive do
            :release_retirement -> :ok
          after
            2_000 -> :ok
          end

        _ ->
          :ok
      end

      debug_state
    end

    assert :ok = :sys.install(control, {hook, 0})
    probe = handoff(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, probe)
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        Enforcer.apply(capability, candidate.snapshot, 1_500)
      end)

    assert_receive :retirement_blocked, 1_000
    Process.send_after(control, :release_retirement, 600)
    assert {:error, :policy_not_ready} = Task.await(task, 1_500)
    assert {:ok, %{allocation_generation: ^generation}} = SpeechToText.input_binding(capability)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, handoff(capability))
  end

  test "automatic attachment rejects the source intervals captured before a transition" do
    {capability, generation, frame} = capability(:ok)
    source = %{track_id: frame.track_id, source_epoch: frame.source_epoch}
    changed = put_in(policy(1, ["human"]).effective.record_audio, false)
    assert :ok = Enforcer.apply(capability, changed, 1_000)
    stale = handoff(capability)

    assert {:error, :unavailable} =
             SpeechToText.attach_diagnostics(capability, generation, {0, 0}, source, stale)

    assert :ok = SpeechToText.push_audio(capability, frame)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    current = handoff(capability)
    assert :ok = SpeechToText.attach_diagnostics(capability, generation, {0, 1}, source, current)
    assert :ok = SpeechToText.push_audio(capability, %{frame | sequence_number: 2})
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:audio, _}, _}
  end

  test "invalid discovered attachment cannot terminate the speech capability" do
    {capability, generation, frame} = capability(:ok)

    assert {:error, :unavailable} =
             SpeechToText.attach_diagnostics(
               capability,
               generation,
               0,
               %{track_id: frame.track_id, source_epoch: frame.source_epoch},
               nil,
               make_ref()
             )

    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:probe_input, _}
  end

  test "missing diagnostic track metadata cannot change accepted speech input" do
    {capability, _generation, frame} = capability(:ok)
    assert :ok = SpeechToText.discover_input_diagnostics(capability, handoff(capability))
    assert :ok = SpeechToText.push_audio(capability, Map.delete(frame, :track_id))
    assert_receive {:probe_input, _}
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  defp attach(capability, generation, frame, handoff),
    do:
      SpeechToText.attach_diagnostics(
        capability,
        generation,
        %{track_id: frame.track_id, source_epoch: frame.source_epoch},
        handoff
      )

  defp handoff(owner, options \\ []) do
    assert {:ok, handoff} =
             CaptureHandoff.new(
               self(),
               options |> Keyword.put(:projection, @projection) |> Keyword.put(:owner, owner)
             )

    handoff
  end

  defp capability(input_result, options \\ []) do
    initial = Keyword.get(options, :initial_policy, policy(0, ["human"]))
    incarnation = Keyword.get(options, :incarnation_id, "incarnation")
    tree = start_supervised!({CapabilityTree, owner: self()})

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: incarnation,
         participant_id: "human",
         connection_id: "connection",
         speech_scope: CapabilityTree.scope(tree),
         provider: {SpeechSessionProbe, [sample_rate: 16_000]},
         provider_private: [observer: self(), input_result: input_result],
         initial_policy: initial}
      )

    assert_receive {:probe_initializing, _, _}
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}
    assert :ok = Enforcer.apply(capability, initial, 1_000)
    assert {:ok, %{allocation_generation: generation}} = SpeechToText.input_binding(capability)

    frame = %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: incarnation,
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      source_epoch: make_ref(),
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 0,
      payload: <<0, 0, 1, 0>>,
      received_at: System.monotonic_time(:millisecond)
    }

    {capability, generation, frame}
  end

  defp policy(revision, participants),
    do: %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(participants),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }
end
