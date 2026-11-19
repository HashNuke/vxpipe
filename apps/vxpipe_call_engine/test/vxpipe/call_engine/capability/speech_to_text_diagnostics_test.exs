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
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _}
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
