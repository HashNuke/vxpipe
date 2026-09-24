defmodule Vxpipe.CallEngine.RoomAuthority.STSTranscriptModesTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallStarted,
    ToolCallCompleted
  }

  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.ActivityControl
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.{STSSession, STTSession}
  alias Vxpipe.Providers.Google.STSSession, as: GoogleSTS
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.TestGoogleSTSTransport

  @morse [unit_duration_ms: 20]
  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      original
      |> Keyword.put(:speech_to_speech, providers: %{STSSession => [enabled: true]})
      |> Keyword.put(:speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            media_ingress: [
              maximum_frames: 25,
              maximum_bytes: 65_536,
              maximum_age_ms: 1_000,
              maximum_consecutive_overflows: 3
            ]
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
  end

  for human_stt? <- [false, true], output_stt? <- [false, true] do
    test "one room round trip with human STT #{human_stt?} and agent-output STT #{output_stt?}" do
      context = room(unquote(human_stt?), unquote(output_stt?))

      if unquote(human_stt?) do
        push_human_stt(context)
        assert_caller_text(context)
      else
        assert context.attachment.media_ingress == nil
      end

      push_sts(context)
      unless unquote(human_stt?), do: assert_caller_text(context)
      output = collect_output(context.sink, [])
      settle_and_assert_reply(context, output)
    end
  end

  test "provider-controlled room ignores a delayed caller signal from an old STT allocation" do
    context = room(true, false)
    state = :sys.get_state(context.authority)
    connection = Map.fetch!(state.connections, context.command.connection_id)
    stt = connection.speech_to_text.capability

    assert {:ok, %{allocation_generation: current_generation}} =
             SpeechToText.input_binding(stt)

    old_signal = %Signal{
      kind: :turn_started,
      provider_sequence: 100,
      allocation_generation: make_ref(),
      turn_ref: make_ref(),
      provider_turn_index: 0,
      policy_revision: :sys.get_state(stt).policy_revision,
      text: "OLD"
    }

    refute old_signal.allocation_generation == current_generation

    identity =
      Map.take(connection.attach_command, [
        :tenant_id,
        :room_id,
        :incarnation_id,
        :participant_id,
        :connection_id
      ])

    send(context.authority, {:vxpipe_stt_signal, stt, identity, old_signal})
    _ = :sys.get_state(context.authority)

    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_received {:vxpipe_event, %ParticipantTranscription{}}

    assert :sys.get_state(context.authority)
           |> Map.fetch!(:connections)
           |> Map.fetch!(context.command.connection_id)
           |> Map.fetch!(:speech_to_text)
           |> Map.fetch!(:turn) == nil
  end

  test "provider-controlled room retires and rebinds selected caller STT across a source cutover" do
    context = room(true, false, %{}, :morse, "provider", :no_transcripts, true)
    state = :sys.get_state(context.authority)
    connection = Map.fetch!(state.connections, context.command.connection_id)
    old_capability = connection.speech_to_text.capability
    old_ingress = connection.speech_to_text.ingress
    fixture = connection.pid

    assert {:ok, %{allocation_generation: old_generation}} =
             SpeechToText.input_binding(old_capability)

    privacy = Map.fetch!(state.participant_transfer_runtime.plan.participants, "privacy")

    # A transcript-interval change rotates the selected STT origin and asks the
    # room to cut its exact source connection over.
    assert {:ok, _policy} =
             MediaPolicyAuthority.admit(state.media_policy_authority, privacy.participant_id)

    assert_receive {:test_sts_source_hold, ^fixture, hold_scope}, 5_000
    assert hold_scope.attachment == connection.room_monitor

    # Both input lanes are closed before the recognizer is retired.
    assert :closed == :sys.get_state(old_ingress).opening_input_admission
    assert :sys.get_state(context.ingress).open? == false

    receipt = %{
      attachment: hold_scope.attachment,
      token: hold_scope.token,
      receiver: self(),
      old_epoch: make_ref(),
      held_epoch: make_ref()
    }

    assert :ok = TestTransferConnection.complete_source_hold(fixture, {:ok, receipt})

    # The room retires the old recognizer, waits for the fresh ready generation,
    # and only then asks the source to arm.
    assert_receive {:test_sts_source_arm, ^fixture, arm_scope}, 5_000
    assert arm_scope.attachment == hold_scope.attachment
    assert arm_scope.token == hold_scope.token
    assert arm_scope.receipt == receipt
    assert is_reference(arm_scope.active_epoch)

    assert :ok =
             TestTransferConnection.complete_source_arm(fixture, {:ok, arm_scope.active_epoch})

    reopened =
      Enum.reduce_while(1..200, nil, fn _, _ ->
        state = :sys.get_state(context.authority)

        case state.speech_to_speech_capability do
          %{ingress: ingress, input_epoch: epoch}
          when is_pid(ingress) and is_reference(epoch) ->
            if state.source_cutover == nil,
              do: {:halt, state},
              else: {:cont, nil}

          _pending ->
            {:cont, nil}
        end
      end)

    assert is_map(reopened)

    fresh_connection = Map.fetch!(reopened.connections, context.command.connection_id)
    fresh_capability = fresh_connection.speech_to_text.capability
    fresh_ingress = fresh_connection.speech_to_text.ingress

    # A transcript-interval policy change replaces the capability's provider
    # session in place; the room waits for that fresh allocation before arming.
    assert fresh_ingress == old_ingress

    assert {:ok, %{allocation_generation: fresh_generation}} =
             SpeechToText.input_binding(fresh_capability)

    assert fresh_generation != old_generation
    assert :open == :sys.get_state(fresh_ingress).opening_input_admission
    assert :sys.get_state(fresh_ingress).source_epoch == arm_scope.active_epoch
    assert :sys.get_state(context.ingress).open? == true

    # A delayed signal from the retired generation cannot open a caller turn.
    old_signal = %Signal{
      kind: :turn_started,
      provider_sequence: 200,
      allocation_generation: old_generation,
      turn_ref: make_ref(),
      provider_turn_index: 0,
      policy_revision: :sys.get_state(old_capability).policy_revision,
      text: "OLD"
    }

    identity =
      Map.take(fresh_connection.attach_command, [
        :tenant_id,
        :room_id,
        :incarnation_id,
        :participant_id,
        :connection_id
      ])

    send(context.authority, {:vxpipe_stt_signal, old_capability, identity, old_signal})
    _ = :sys.get_state(context.authority)
    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}

    # A fresh caller turn publishes exactly one caller pair and one agent reply.
    fresh =
      context
      |> Map.put(:attachment, TestTransferConnection.attachment(context.command))
      |> Map.put(:source_epoch, arm_scope.active_epoch)

    push_sts(fresh)
    push_selected_stt(fresh)
    assert_caller_text(context)
    output = collect_output(context.sink, [])
    settle_and_assert_reply(context, output)
  end

  test "delayed human recognition onset cannot interrupt a newer provider-driven reply" do
    context = room(true, false)
    assert :ok = :sys.suspend(context.authority)

    output =
      try do
        push_human_stt(context)
        push_sts(context)
        collect_output(context.sink, [])
      after
        :sys.resume(context.authority)
      end

    assert_caller_text(context)
    _ = :sys.get_state(context.authority)
    refute_received {:test_audio_output_interrupt, _, _, _}
    refute_received {:vxpipe_event, %AgentTurnInterrupted{}}
    settle_and_assert_reply(context, output)
  end

  test "external room control waits for the selected human-STT end boundary" do
    context = room(true, false, %{}, :morse, "external")

    push_sts(context)
    refute_received {:test_audio_output_finish, _, _}

    push_human_stt(context)
    assert_caller_text(context)
    output = collect_output(context.sink, [])
    settle_and_assert_reply(context, output)
  end

  test "hybrid room control uses provider onset and the selected human-STT end" do
    context = room(true, false, %{}, :morse, "hybrid")

    push_sts(context)
    refute_received {:test_audio_output_finish, _, _}

    push_human_stt(context)
    assert_caller_text(context)
    output = collect_output(context.sink, [])
    settle_and_assert_reply(context, output)
  end

  test "external room hold retires an idle STS allocation before old STT evidence can control a new epoch" do
    context = room(true, false, %{}, :morse, "external")
    before_hold = :sys.get_state(context.authority)
    connection = Map.fetch!(before_hold.connections, context.command.connection_id)
    stt = connection.speech_to_text.capability

    assert {:ok, %{activity_origin: %{allocation_generation: generation} = origin}} =
             SpeechToText.input_binding(stt)

    monitor = Process.monitor(context.capability)
    held = :sys.replace_state(context.authority, &SpeechToSpeech.hold/1)
    assert held.speech_to_speech_capability == nil
    assert_receive {:DOWN, ^monitor, :process, _, _reason}

    assert {:ok, %{activity_origin: %{allocation_generation: ^generation}}} =
             SpeechToText.input_binding(stt)

    released = :sys.replace_state(context.authority, &SpeechToSpeech.release/1)
    assert released.speech_to_speech_capability == nil

    delayed = %Signal{
      kind: :turn_started,
      provider_sequence: 1,
      allocation_generation: generation,
      turn_ref: make_ref(),
      audio_input_interval: origin.audio_input_interval,
      audio_output_interval: origin.audio_output_interval
    }

    assert ActivityControl.start(released, context.command.connection_id, delayed) == released
  end

  test "external room control rejects a stale STT allocation generation" do
    context = room(true, false, %{}, :morse, "external")
    state = :sys.get_state(context.authority)
    connection = Map.fetch!(state.connections, context.command.connection_id)

    assert {:ok, %{activity_origin: origin}} =
             SpeechToText.input_binding(connection.speech_to_text.capability)

    signal = %Signal{
      kind: :turn_started,
      provider_sequence: 1,
      allocation_generation: make_ref(),
      turn_ref: make_ref(),
      audio_input_interval: origin.audio_input_interval,
      audio_output_interval: origin.audio_output_interval
    }

    assert ActivityControl.start(state, context.command.connection_id, signal) == state
    assert :sys.get_state(context.provider).external_started? == false
  end

  test "a rejected current external boundary fails its STS allocation closed" do
    context = room(true, false, %{}, :morse, "external")
    state = :sys.get_state(context.authority)
    connection = Map.fetch!(state.connections, context.command.connection_id)

    assert {:ok, %{activity_origin: origin}} =
             SpeechToText.input_binding(connection.speech_to_text.capability)

    signal = %Signal{
      kind: :turn_started,
      provider_sequence: 1,
      allocation_generation: origin.allocation_generation,
      turn_ref: make_ref(),
      audio_input_interval: origin.audio_input_interval,
      audio_output_interval: origin.audio_output_interval
    }

    assert :ok = STSIngress.hold(context.ingress)
    monitor = Process.monitor(context.capability)
    next = ActivityControl.start(state, context.command.connection_id, signal)
    assert next.speech_to_speech_capability == nil
    assert_receive {:DOWN, ^monitor, :process, _, _reason}
  end

  test "a rejected matching external end fails its STS allocation closed" do
    context = room(true, false, %{}, :morse, "external")
    state = :sys.get_state(context.authority)
    connection = Map.fetch!(state.connections, context.command.connection_id)

    assert {:ok, %{activity_origin: origin}} =
             SpeechToText.input_binding(connection.speech_to_text.capability)

    signal = %Signal{
      kind: :turn_started,
      provider_sequence: 1,
      allocation_generation: origin.allocation_generation,
      turn_ref: make_ref(),
      audio_input_interval: origin.audio_input_interval,
      audio_output_interval: origin.audio_output_interval
    }

    started = ActivityControl.start(state, context.command.connection_id, signal)
    assert %{activity_turn: %{turn_ref: turn_ref}} = started.speech_to_speech_capability
    assert turn_ref == signal.turn_ref
    _ = :sys.get_state(context.capability)

    assert :ok = STSIngress.hold(context.ingress)
    monitor = Process.monitor(context.capability)
    finished = ActivityControl.finish(started, context.command.connection_id, signal)
    assert finished.speech_to_speech_capability == nil
    assert_receive {:DOWN, ^monitor, :process, _, _reason}
  end

  for mode <- ["external", "hybrid"], delayed? <- [false, true] do
    test "#{mode} activity survives STT replacement with delayed onset #{delayed?}" do
      context = room(true, false, %{}, :morse, unquote(mode), true)
      assert {:ok, old_pcm} = Encoder.encode(context.config, "NO")
      state = :sys.get_state(context.authority)
      connection = Map.fetch!(state.connections, context.command.connection_id)
      stt = connection.speech_to_text.capability

      assert {:ok, %{activity_origin: before, identity: identity}} =
               SpeechToText.input_binding(stt)

      if unquote(delayed?), do: :sys.suspend(context.authority)

      old_turn_ref =
        try do
          push_selected_stt(%{context | pcm: binary_part(context.pcm, 0, 640)})
          push_sts(%{context | pcm: old_pcm})
          _ = :sys.get_state(context.attachment.media_ingress)
          _ = :sys.get_state(stt)
          _ = :sys.get_state(Session.provider(:sys.get_state(stt).session))
          _ = :sys.get_state(stt)
          old_turn_ref = :sys.get_state(Session.provider(:sys.get_state(stt).session)).turn_ref
          assert is_reference(old_turn_ref)

          if unquote(delayed?) do
            {:messages, messages} = Process.info(context.authority, :messages)

            assert Enum.any?(messages, fn
                     {:vxpipe_stt_signal, ^stt, _, %Signal{kind: :turn_started}} -> true
                     _ -> false
                   end)
          else
            assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}, 1_000

            assert is_map(
                     :sys.get_state(context.authority).speech_to_speech_capability.activity_turn
                   )
          end

          privacy = Map.fetch!(state.participant_transfer_runtime.plan.participants, "privacy")

          assert {:ok, policy} =
                   MediaPolicyAuthority.admit(
                     state.media_policy_authority,
                     privacy.participant_id
                   )

          refute policy.effective.record_audio
          assert MapSet.member?(policy.present_participant_ids, context.agent)
          assert MapSet.member?(policy.present_participant_ids, context.caller)

          fresh = await_new_stt_origin(stt, before.allocation_generation)
          assert is_map(fresh)
          old_turn_ref
        after
          if unquote(delayed?), do: :sys.resume(context.authority)
        end

      _ = :sys.get_state(context.authority)
      if unquote(delayed?), do: refute_received({:vxpipe_event, %ParticipantTurnStarted{}})

      rebound =
        Enum.reduce_while(1..200, nil, fn _, _ ->
          state = :sys.get_state(context.authority)

          case state.speech_to_speech_capability do
            %{pid: capability, ingress: ingress, input_epoch: epoch}
            when capability != context.capability and is_pid(ingress) and is_reference(epoch) ->
              {:halt, %{context | capability: capability, ingress: ingress}}

            _pending ->
              {:cont, nil}
          end
        end)

      assert is_map(rebound),
             inspect(
               Map.take(:sys.get_state(context.authority), [
                 :speech_to_speech_recovery,
                 :speech_to_speech_capability,
                 :speech_to_speech_ready?,
                 :startup_ready?
               ])
             )

      send(context.authority, {:vxpipe_sts_activity_origin_changed, context.capability, 999})

      assert :sys.get_state(context.authority).speech_to_speech_capability.pid ==
               rebound.capability

      push_sts(rebound)
      push_selected_stt(%{context | pcm: binary_part(context.pcm, 0, 640)})

      fresh_turn =
        Enum.reduce_while(1..200, nil, fn _, _ ->
          turn = :sys.get_state(context.authority).speech_to_speech_capability.activity_turn
          if is_map(turn), do: {:halt, turn}, else: {:cont, nil}
        end)

      assert is_map(fresh_turn)

      old_end = %Signal{
        kind: :turn_ended,
        provider_sequence: 99,
        allocation_generation: before.allocation_generation,
        turn_ref: old_turn_ref,
        audio_input_interval: before.audio_input_interval,
        audio_output_interval: before.audio_output_interval,
        policy_revision: 0,
        provider_turn_index: 0,
        text: "NO"
      }

      send(context.authority, {:vxpipe_stt_signal, stt, identity, old_end})

      assert :sys.get_state(context.authority).speech_to_speech_capability.activity_turn ==
               fresh_turn

      refute_received {:vxpipe_event, %ParticipantTurnCompleted{}}

      push_selected_stt(
        %{context | pcm: binary_part(context.pcm, 640, byte_size(context.pcm) - 640)},
        1
      )

      assert_caller_text(context)
      output = collect_output(rebound.sink, [])
      settle_and_assert_reply(rebound, output)
    end
  end

  for mode <- ["external", "hybrid"] do
    test "#{mode} ignores a queued old STT onset after activity demand disappears" do
      context = room(true, false, %{}, :morse, unquote(mode), :deny_audio)
      state = :sys.get_state(context.authority)
      connection = Map.fetch!(state.connections, context.command.connection_id)
      stt = connection.speech_to_text.capability
      monitor = Process.monitor(context.authority)
      assert :ok = :sys.suspend(context.authority)

      try do
        push_selected_stt(%{context | pcm: binary_part(context.pcm, 0, 640)})
        _ = :sys.get_state(context.attachment.media_ingress)
        _ = :sys.get_state(stt)
        _ = :sys.get_state(Session.provider(:sys.get_state(stt).session))
        _ = :sys.get_state(stt)

        {:messages, messages} = Process.info(context.authority, :messages)

        assert Enum.any?(messages, fn
                 {:vxpipe_stt_signal, ^stt, _, %Signal{kind: :turn_started}} -> true
                 _ -> false
               end)

        privacy = Map.fetch!(state.participant_transfer_runtime.plan.participants, "privacy")

        assert {:ok, _policy} =
                 MediaPolicyAuthority.admit(state.media_policy_authority, privacy.participant_id)

        assert {:ok, %{activity_origin: nil}} = SpeechToText.input_binding(stt)
      after
        :sys.resume(context.authority)
      end

      assert %{speech_to_speech_capability: nil} = closed = :sys.get_state(context.authority)
      assert SpeechToSpeech.recover(closed) == closed
      refute_received {:DOWN, ^monitor, :process, _, _reason}
      refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    end
  end

  for mode <- ["external", "hybrid"] do
    test "#{mode} retires an active controller when activity demand disappears" do
      context = room(true, false, %{}, :morse, unquote(mode), :deny_audio)
      state = :sys.get_state(context.authority)
      connection = Map.fetch!(state.connections, context.command.connection_id)
      stt = connection.speech_to_text.capability

      assert {:ok, %{activity_origin: origin, identity: identity}} =
               SpeechToText.input_binding(stt)

      assert {:ok, old_pcm} = Encoder.encode(context.config, "NO")
      caller = context.caller

      push_selected_stt(%{context | pcm: binary_part(context.pcm, 0, 640)})
      push_sts(%{context | pcm: old_pcm})
      assert_receive {:vxpipe_event, %ParticipantTurnStarted{participant_id: ^caller}}, 1_000

      active = :sys.get_state(context.authority)
      assert %{activity_turn: turn} = active.speech_to_speech_capability

      caller_turn =
        Map.fetch!(active.connections, context.command.connection_id).speech_to_text.turn

      assert is_reference(turn.turn_ref)
      assert turn.turn_ref == caller_turn.turn_ref
      assert turn.generation == origin.allocation_generation
      assert turn.source == context.command.connection_id

      monitor = Process.monitor(context.capability)
      privacy = Map.fetch!(state.participant_transfer_runtime.plan.participants, "privacy")

      assert {:ok, _policy} =
               MediaPolicyAuthority.admit(state.media_policy_authority, privacy.participant_id)

      assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
      assert %{speech_to_speech_capability: nil} = :sys.get_state(context.authority)
      assert {:ok, %{activity_origin: nil}} = SpeechToText.input_binding(stt)

      old_end = %Signal{
        kind: :turn_ended,
        provider_sequence: 99,
        allocation_generation: origin.allocation_generation,
        turn_ref: turn.turn_ref,
        audio_input_interval: origin.audio_input_interval,
        audio_output_interval: origin.audio_output_interval,
        policy_revision: caller_turn.policy_revision,
        provider_turn_index: caller_turn.provider_turn_index,
        text: "NO"
      }

      send(context.authority, {:vxpipe_stt_signal, stt, identity, old_end})
      assert %{speech_to_speech_capability: nil} = :sys.get_state(context.authority)
      _ = :sys.get_state(context.sink)
      _ = :sys.get_state(context.authority)
      sink = context.sink
      refute_received {:test_audio_output, ^sink, _}
      refute_received {:test_audio_output_finish, ^sink, _}
      refute_received {:vxpipe_event, %AgentSpeechStarted{}}
      refute_received {:vxpipe_event, %AgentTurnCompleted{}}
    end
  end

  for mode <- ["external", "hybrid"] do
    test "#{mode} replaces an active pair after transcript-only STT rotation" do
      context = room(true, false, %{}, :morse, unquote(mode), :no_transcripts)
      assert {:ok, old_pcm} = Encoder.encode(context.config, "NO")
      state = :sys.get_state(context.authority)
      connection = Map.fetch!(state.connections, context.command.connection_id)
      stt = connection.speech_to_text.capability
      assert {:ok, %{activity_origin: before}} = SpeechToText.input_binding(stt)

      push_selected_stt(%{context | pcm: binary_part(context.pcm, 0, 640)})
      push_sts(%{context | pcm: old_pcm})
      assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}, 1_000
      assert is_map(:sys.get_state(context.authority).speech_to_speech_capability.activity_turn)

      privacy = Map.fetch!(state.participant_transfer_runtime.plan.participants, "privacy")

      assert {:ok, policy} =
               MediaPolicyAuthority.admit(state.media_policy_authority, privacy.participant_id)

      refute policy.effective.save_transcripts

      fresh = await_new_stt_origin(stt, before.allocation_generation)
      assert is_map(fresh)
      assert fresh.audio_input_interval == before.audio_input_interval
      assert fresh.audio_output_interval == before.audio_output_interval

      rebound =
        Enum.reduce_while(1..200, nil, fn _, _ ->
          case :sys.get_state(context.authority).speech_to_speech_capability do
            %{pid: capability, ingress: ingress, input_epoch: epoch}
            when capability != context.capability and is_pid(ingress) and is_reference(epoch) ->
              {:halt, %{context | capability: capability, ingress: ingress}}

            _pending ->
              {:cont, nil}
          end
        end)

      assert is_map(rebound)
      push_sts(rebound)
      push_selected_stt(context)
      assert_caller_text(context)
      output = collect_output(rebound.sink, [])
      settle_and_assert_reply(rebound, output)
    end
  end

  for mode <- ["external", "hybrid"] do
    test "#{mode} replaces an active pair after selected agent presence loss and regrant" do
      context = room(true, false, %{}, :morse, unquote(mode))
      assert {:ok, old_pcm} = Encoder.encode(context.config, "NO")
      state = :sys.get_state(context.authority)
      connection = Map.fetch!(state.connections, context.command.connection_id)
      stt = connection.speech_to_text.capability
      policy_before = MediaPolicyAuthority.snapshot(state.media_policy_authority)
      assert {:ok, %{activity_origin: before}} = SpeechToText.input_binding(stt)

      push_selected_stt(%{context | pcm: binary_part(context.pcm, 0, 640)})
      push_sts(%{context | pcm: old_pcm})
      assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}, 1_000
      assert is_map(:sys.get_state(context.authority).speech_to_speech_capability.activity_turn)

      assert {:ok, absent} =
               MediaPolicyAuthority.leave(state.media_policy_authority, context.agent)

      refute MapSet.member?(absent.present_participant_ids, context.agent)

      assert {:ok, restored} =
               MediaPolicyAuthority.admit(state.media_policy_authority, context.agent)

      assert MapSet.member?(restored.present_participant_ids, context.agent)

      assert Snapshot.interval(restored, :audio_input, context.caller) ==
               before.audio_input_interval

      assert Snapshot.interval(restored, :audio_output, context.caller) ==
               before.audio_output_interval

      assert Snapshot.interval(restored, :speech_to_text, context.caller) ==
               Snapshot.interval(policy_before, :speech_to_text, context.caller)

      fresh = await_new_stt_origin(stt, before.allocation_generation)
      assert is_map(fresh)

      rebound =
        Enum.reduce_while(1..200, nil, fn _, _ ->
          case :sys.get_state(context.authority).speech_to_speech_capability do
            %{pid: capability, ingress: ingress, input_epoch: epoch}
            when capability != context.capability and is_pid(ingress) and is_reference(epoch) ->
              {:halt, %{context | capability: capability, ingress: ingress}}

            _pending ->
              {:cont, nil}
          end
        end)

      assert is_map(rebound)
      push_sts(rebound)
      push_selected_stt(context)
      assert_caller_text(context)
      output = collect_output(rebound.sink, [])
      settle_and_assert_reply(rebound, output)
    end
  end

  for mode <- ["external", "hybrid"] do
    test "#{mode} keeps permitted human transcription after STS audio is denied" do
      context = room(true, false, %{}, :morse, unquote(mode), :deny_audio)
      state = :sys.get_state(context.authority)
      connection = Map.fetch!(state.connections, context.command.connection_id)
      stt = connection.speech_to_text.capability
      assert {:ok, %{audio_origin: before}} = SpeechToText.input_binding(stt)
      privacy = Map.fetch!(state.participant_transfer_runtime.plan.participants, "privacy")

      assert {:ok, policy} =
               MediaPolicyAuthority.admit(state.media_policy_authority, privacy.participant_id)

      assert policy.effective.transcript_routes == :unrestricted

      assert %{allocation_generation: generation} =
               await_new_stt_origin(stt, before.allocation_generation, :audio_origin)

      assert generation != before.allocation_generation
      assert {:ok, %{activity_origin: nil}} = SpeechToText.input_binding(stt)
      assert %{speech_to_speech_capability: nil} = :sys.get_state(context.authority)

      push_selected_stt(context)
      caller = context.caller

      assert_receive {:vxpipe_event,
                      %ParticipantTranscription{participant_id: ^caller, text: "HI", final: true}},
                     1_000

      refute_received {:test_audio_output_finish, _, _}
      refute_received {:vxpipe_event, %AgentTurnCompleted{}}
    end
  end

  test "reopening already-open room input preserves its caller publication epoch" do
    context = room(false, false)
    state = :sys.get_state(context.authority)
    epoch = state.speech_to_speech_capability.input_epoch
    assert is_reference(epoch)
    assert Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.release(state) == state
    assert :sys.get_state(context.capability).input_epoch == epoch
  end

  test "Google final arriving after reply playback retains room-owned caller identity" do
    context = room(false, false, %{}, :google)
    caller = context.caller
    agent = context.agent
    google_deliver(context, %{"voiceActivity" => %{"type" => "ACTIVITY_START"}})

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{participant_id: ^caller} = started},
                   1_000

    google_deliver(context, %{"voiceActivity" => %{"type" => "ACTIVITY_END"}})

    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{participant_id: ^caller} = ended},
                   1_000

    refute_received {:vxpipe_event, %ParticipantTranscription{final: true}}

    pcm = :binary.copy(<<1, 0>>, 480)

    google_deliver(context, %{
      "serverContent" => %{
        "outputTranscription" => %{"text" => "REPLY"},
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(pcm)
              }
            }
          ]
        },
        "generationComplete" => true
      }
    })

    assert collect_output(context.sink, []) == pcm
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, 20, 20)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)
    assert_receive {:vxpipe_event, %TextOutput{participant_id: ^agent, text: "REPLY"}}, 1_000
    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: ^agent}}, 1_000
    _ = :sys.get_state(context.provider)

    google_deliver(context, %{"serverContent" => %{"inputTranscription" => %{"text" => "CALLER"}}})

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: ^caller,
                      text: "CALLER",
                      final: true
                    } = text},
                   1_000

    assert String.starts_with?(text.correlation_id, "turn_")
    assert String.starts_with?(text.command_id, "cmd_")
    assert text.correlation_id == started.correlation_id
    assert ended.correlation_id == started.correlation_id
    assert text.command_id == started.command_id
    assert ended.command_id == started.command_id
    assert text.connection_id == context.command.connection_id
    assert ended.sequence < text.sequence
    assert :sys.get_state(context.authority).sts_caller_turns == %{}
    assert :sys.get_state(context.capability).caller_turns == %{}
    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_received {:vxpipe_event, %ParticipantTurnCompleted{}}
    refute_received {:vxpipe_event, %ParticipantTranscription{final: true}}
  end

  test "a live Morse STS room tool uses public IDs throughout execution and settlement" do
    context = room(false, false, %{"echo_context" => %{type: "host", tool: "echo_context"}})

    assert :ok =
             CallEngine.Capability.SpeechToSpeech.push_text(
               context.capability,
               "TOOL echo_context {}"
             )

    assert_receive {:vxpipe_event, %ToolCallStarted{} = started}, 1_000
    assert_receive {:vxpipe_event, %ToolCallCompleted{} = completed}, 1_000
    assert String.starts_with?(started.tool_call_id, "tlatt_")
    assert String.starts_with?(started.command_id, "cmd_")
    assert String.starts_with?(started.correlation_id, "turn_")
    assert completed.tool_call_id == started.tool_call_id
    assert completed.command_id == started.command_id
    assert completed.correlation_id == started.correlation_id

    assert completed.result == %{
             "tool_call_id" => started.tool_call_id,
             "command_id" => started.command_id,
             "correlation_id" => started.correlation_id,
             "connection_id" => context.command.connection_id,
             "agent_id" => context.agent
           }

    assert :sys.get_state(context.authority).sts_tool_calls == %{}
    assert :sys.get_state(context.capability).tool_calls == %{}
    refute_received {:vxpipe_event, %AgentSpeechStarted{}}
    refute_received {:vxpipe_event, %ToolCallStarted{}}
    refute_received {:vxpipe_event, %ToolCallCompleted{}}
  end

  defp room(
         human_stt?,
         output_stt?,
         tools \\ %{},
         provider \\ :morse,
         turn_control \\ "provider",
         recording_toggle? \\ false,
         source_control? \\ false
       ) do
    plan = compile_plan(human_stt?, output_stt?, tools, turn_control, recording_toggle?)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    install_google_fixture(authority, provider)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _attachment} =
             TestTransferConnection.attach(command, sink,
               input_track: @track,
               source_control?: source_control?
             )

    wire = google_ready(provider)
    TestCallStartup.await_ready(plan.room_id)
    attachment = TestTransferConnection.attachment(command)

    assert {:ok, %{ingress: ingress}} =
             CallEngine.speech_to_speech_input_configuration(attachment)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    assert {:ok, config} = Config.new(@morse)
    assert {:ok, pcm} = Encoder.encode(config, "HI")

    %{
      attachment: attachment,
      command: command,
      sink: sink,
      config: config,
      pcm: pcm,
      capability: capability,
      wire: wire,
      provider: Session.provider(:sys.get_state(capability).session),
      ingress: ingress,
      authority: authority,
      caller: caller.participant_id,
      agent: agent.participant_id
    }
  end

  defp install_google_fixture(_authority, :morse), do: :ok

  defp install_google_fixture(authority, :google) do
    assert {:error, :unsupported_provider_capability} =
             Vxpipe.Providers.Registry.fetch_capability("google", :sts)

    assert {:ok, config} = Vxpipe.Providers.Google.STS.new(api_key: "synthetic-room-key")
    observer = self()

    # Replace only the prepared private test runtime before source attachment.
    # This exercises room allocation/publication, not gated production selection.
    :sys.replace_state(authority, fn state ->
      runtime = %{
        state.speech_to_speech_runtime
        | provider: {GoogleSTS, []},
          provider_private: [
            config: config,
            wire_module: TestGoogleSTSTransport,
            wire_options: [observer: observer]
          ]
      }

      %{state | speech_to_speech_runtime: runtime}
    end)
  end

  defp google_ready(:morse), do: nil

  defp google_ready(:google) do
    assert_receive {:test_google_sts_started, wire, _}, 1_000
    assert_receive {:test_google_sts_control, ^wire, _}, 1_000
    TestGoogleSTSTransport.deliver(wire, JSON.encode!(%{"setupComplete" => %{}}))
    wire
  end

  defp google_deliver(context, message) do
    TestGoogleSTSTransport.deliver(context.wire, JSON.encode!(message))
    _ = :sys.get_state(context.wire)
    _ = :sys.get_state(context.provider)
    _ = :sys.get_state(context.capability)
    _ = :sys.get_state(context.authority)
  end

  defp push_human_stt(context) do
    assert is_pid(context.attachment.media_ingress)

    assert :ok =
             TestTransferConnection.run(context.command, fn ->
               CallEngine.push_audio(context.attachment, stt_frame(context, context.pcm, 0))
             end)
  end

  defp push_selected_stt(context, sequence \\ 0) do
    result =
      Enum.reduce_while(1..100, nil, fn _, _ ->
        result =
          TestTransferConnection.run(context.command, fn ->
            CallEngine.push_audio(context.attachment, stt_frame(context, context.pcm, sequence))
          end)

        if result == {:error, :stale_frame}, do: {:cont, result}, else: {:halt, result}
      end)

    assert result == :ok
  end

  defp stt_frame(context, pcm, sequence),
    do: frame(context, pcm, sequence, Map.get(context, :source_epoch))

  defp push_sts(context, sequence_offset \\ 0) do
    for {chunk, sequence} <-
          Enum.with_index(
            for(<<chunk::binary-size(320) <- context.pcm>>, do: chunk),
            sequence_offset
          ) do
      assert :ok =
               TestTransferConnection.run(context.command, fn ->
                 CallEngine.push_speech_to_speech_audio(
                   context.attachment,
                   frame(context, chunk, sequence)
                 )
               end)

      settled =
        Enum.reduce_while(1..100, nil, fn _, _ ->
          _ = :sys.get_state(context.capability)
          stats = STSIngress.stats(context.ingress)

          if stats.queued == 0 and not stats.in_flight?,
            do: {:halt, stats},
            else: {:cont, stats}
        end)

      assert %{queued: 0, in_flight?: false, dropped: 0} = settled
    end
  end

  defp frame(context, pcm, sequence, source_epoch \\ nil) do
    identity =
      Map.take(context.command, [
        :tenant_id,
        :room_id,
        :incarnation_id,
        :participant_id,
        :connection_id
      ])

    struct!(
      AudioFrame,
      Map.merge(
        identity,
        Map.merge(@track, %{
          payload: pcm,
          sequence_number: sequence,
          timestamp: sequence * 160,
          source_epoch: source_epoch,
          received_at: System.monotonic_time(:millisecond)
        })
      )
    )
  end

  defp assert_caller_text(context) do
    caller = context.caller

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{participant_id: ^caller, text: "HI", final: true} =
                      text},
                   1_000

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{participant_id: ^caller} = started},
                   1_000

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{participant_id: ^caller} = completed},
                   1_000

    assert String.starts_with?(started.correlation_id, "turn_")
    assert String.starts_with?(started.command_id, "cmd_")
    assert text.correlation_id == started.correlation_id
    assert completed.correlation_id == started.correlation_id
    assert text.command_id == started.command_id
    assert completed.command_id == started.command_id
    assert started.connection_id == context.command.connection_id
    assert started.sequence < text.sequence
    assert text.sequence < completed.sequence
    assert started.modality == :audio
    assert completed.modality == :audio
  end

  defp collect_output(sink, frames) do
    receive do
      {:test_audio_output, ^sink, frame} ->
        collect_output(sink, [frame.payload | frames])

      {:test_audio_output_finish, ^sink, _turn} ->
        frames |> Enum.reverse() |> IO.iodata_to_binary()
    after
      2_000 -> flunk("STS reply did not reach the room sink")
    end
  end

  defp settle_and_assert_reply(context, output) do
    assert {:ok, decoder} = Decoder.new(context.config)
    assert {:ok, _decoder, events} = Decoder.push(decoder, output)
    assert {:final, "RECEIVED HI"} in events
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}, 1_000
    assert String.starts_with?(started.correlation_id, "turn_")
    assert String.starts_with?(started.command_id, "cmd_")
    assert started.connection_id == context.command.connection_id
    refute_received {:vxpipe_event, %TextOutput{}}
    played = div(byte_size(output) * 1_000, 16_000 * 2)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, played, played)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)
    agent = context.agent

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^agent,
                      source_participant_id: ^agent,
                      text: "RECEIVED HI",
                      will_be_spoken: true
                    } = text},
                   1_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: ^agent} = completed}, 1_000
    assert text.correlation_id == started.correlation_id
    assert completed.correlation_id == started.correlation_id
    assert text.command_id == started.command_id
    assert completed.command_id == started.command_id
    _ = :sys.get_state(context.capability)
    _ = :sys.get_state(context.authority)
    _ = TestTransferConnection.run(context.command, fn -> :ok end)
    refute_received {:vxpipe_event, %ParticipantTranscription{final: true}}
    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_received {:vxpipe_event, %ParticipantTurnCompleted{}}
    refute_received {:vxpipe_event, %TextOutput{}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{}}
    refute_received {:vxpipe_event, %AgentTurnInterrupted{}}
  end

  defp compile_plan(human_stt?, output_stt?, tools, turn_control, recording_toggle?) do
    speech = %{provider: "morse", model: "morse", options: Map.new(@morse)}

    agent = %{
      speech_to_speech:
        speech
        |> put_in([:options, :output_transcript], not output_stt?)
        |> put_in([:options, :turn_control], turn_control)
    }

    agent = if output_stt?, do: Map.put(agent, :output_speech_to_text, speech), else: agent

    participants = %{
      "caller" => %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "start_call"},
        capabilities: if(human_stt?, do: %{speech_to_text: speech}, else: %{})
      },
      "assistant" => %{
        type: "agent",
        prompt: "Reply in Morse.",
        tools: tools,
        transfers: [],
        first_message: %{mode: "wait_for_input"},
        capabilities: agent
      }
    }

    privacy_settings = privacy_settings(recording_toggle?)

    participants =
      if privacy_settings != nil do
        Map.put(participants, "privacy", %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{},
          while_present: privacy_settings
        })
      else
        participants
      end

    source = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: participants
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-modes", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-modes", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-modes",
               actor_id: "actor-sts-modes"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(spec, invocation, %{
               host_tools: %{"echo_context" => CallEngine.STSContextTool}
             })

    plan
  end

  defp privacy_settings(false), do: nil
  defp privacy_settings(true), do: %{record_audio: false}
  defp privacy_settings(:deny_audio), do: %{audio_routes: %{}}
  defp privacy_settings(:no_transcripts), do: %{save_transcripts: false}

  defp await_new_stt_origin(stt, old_generation, field \\ :activity_origin) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    poll_stt_origin(stt, old_generation, field, deadline)
  end

  defp poll_stt_origin(stt, old_generation, field, deadline) do
    case SpeechToText.input_binding(stt) do
      {:ok, binding} ->
        case Map.get(binding, field) do
          %{allocation_generation: generation} = origin when generation != old_generation ->
            origin

          _pending ->
            wait_stt_origin(stt, old_generation, field, deadline)
        end

      _pending ->
        wait_stt_origin(stt, old_generation, field, deadline)
    end
  end

  defp wait_stt_origin(stt, old_generation, field, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      flunk("selected STT did not replace its native allocation within startup budget")
    else
      receive do
      after
        10 -> poll_stt_origin(stt, old_generation, field, deadline)
      end
    end
  end
end
