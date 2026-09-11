defmodule Vxpipe.Gateway.Telephony.Twilio.MediaSessionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler}
  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket, Submission}
  alias Vxpipe.Calls.{PreparedCall, TelephonyAdmissionClaim}
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.Media.AudioOutput

  alias Vxpipe.Gateway.Telephony.{
    IncomingLegActivationResult,
    MediaBinding,
    MediaSupervisor
  }

  @account_sid "AC00000000000000000000000000000000"
  @call_sid "CA00000000000000000000000000000000"
  @stream_sid "MZ00000000000000000000000000000000"

  test "runs Twilio PCMU in both directions through the common media session" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assistant = Map.fetch!(plan.participants, plan.entry_receiver)
    assert {:ok, room} = CallEngine.start_call(plan)
    socket = socket(self())

    leg =
      start_supervised!(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: :twilio_media_session_leg
      )

    binding = binding(plan, room.incarnation_id, caller.participant_id, leg)
    claim = claim(plan, room.incarnation_id, caller.participant_id)
    root = start_supervised!({MediaSupervisor, name: nil})

    assert :ok =
             CallAdmission.handle_live_event(
               [telephony_media_supervisor: root],
               claim,
               activation(binding),
               socket,
               media_started_event(binding)
             )

    assert {:ok, snapshot} = MediaSupervisor.snapshot(binding.client_state_leg_id)
    assert is_pid(snapshot.audio_output)
    assert is_pid(snapshot.room_audio_ingress)
    assert is_pid(snapshot.room_audio_egress)

    assert :ok =
             AudioOutput.push(
               snapshot.audio_output,
               output_frame(binding, assistant.participant_id)
             )

    assert :ok = AudioOutput.finish(snapshot.audio_output, "turn-phone", self())
    assert_receive {:test_twilio_socket_send, message}, 2_000

    assert %{
             "event" => "media",
             "streamSid" => @stream_sid,
             "media" => %{"payload" => payload}
           } = JSON.decode!(message)

    assert {:ok, pcmu} = Base.decode64(payload)
    assert byte_size(pcmu) == 160
    assert_receive {:vxpipe_audio_playback, _output, "turn-phone", :started}, 2_000
    assert_receive {:vxpipe_audio_playback, _output, "turn-phone", {:completed, 20}}, 2_000

    assert :ok =
             CallAdmission.handle_live_event(
               [],
               claim,
               activation(binding),
               socket,
               media_event(binding)
             )

    assert {:error, :wrong_media_source} =
             CallAdmission.handle_live_event(
               [],
               claim,
               activation(binding),
               self(),
               media_event(binding)
             )
  end

  defp compile_plan do
    definition_input = %{
      schema_version: "20260911.03",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "primary-phone",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(definition_input,
               resource_id: unique_id("definition"),
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: definition.resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "telephony"}
               },
               tenant_id: unique_id("tenant"),
               actor_id: unique_id("actor"),
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "google:test-model"}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp claim(plan, incarnation_id, participant_id) do
    %TelephonyAdmissionClaim{
      call: %PreparedCall{
        id: plan.call_id,
        tenant_key: plan.tenant_id,
        definition_id: plan.definition_id,
        definition_revision: plan.definition_revision,
        schema_version: plan.schema_version,
        participant_routes: %{},
        entry_caller: plan.entry_caller,
        entry_receiver: plan.entry_receiver,
        initial_variables: %{},
        plan: plan,
        plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
        state: :running,
        room_id: plan.room_id,
        created_at: DateTime.utc_now(),
        started_at: DateTime.utc_now(),
        ended_at: nil,
        incarnation_id: incarnation_id,
        terminal_reason: nil
      },
      participant_ref: plan.entry_caller,
      participant_id: participant_id,
      provider: :twilio,
      service: "primary-phone",
      provider_event_id: "event-incoming-1",
      provider_connection_id: @account_sid,
      provider_call_control_id: @call_sid,
      provider_call_leg_id: @call_sid,
      provider_call_session_id: nil,
      accepted_at: DateTime.utc_now()
    }
  end

  defp binding(plan, incarnation_id, participant_id, leg) do
    %MediaBinding{
      provider: :twilio,
      service_id: "primary-phone",
      ingress_key: "ingress-primary",
      tenant_id: plan.tenant_id,
      call_id: plan.call_id,
      room_id: plan.room_id,
      incarnation_id: incarnation_id,
      participant_id: participant_id,
      provider_connection_id: @account_sid,
      provider_call_control_id: @call_sid,
      provider_call_leg_id: @call_sid,
      provider_call_session_id: nil,
      client_state_leg_id: unique_id("connection"),
      leg: leg
    }
  end

  defp activation(binding) do
    %IncomingLegActivationResult{
      binding: binding,
      media_url: "wss://voice.example.test/api/telephony/twilio/media/test",
      submission: %Submission{
        status: :accepted,
        provider_call_control_id: binding.provider_call_control_id,
        provider_call_leg_id: binding.provider_call_leg_id,
        provider_call_session_id: nil
      }
    }
  end

  defp output_frame(binding, speaking_participant_id) do
    %AudioOutputFrame{
      tenant_id: binding.tenant_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: speaking_participant_id,
      connection_id: binding.client_state_leg_id,
      command_id: "command-phone",
      correlation_id: "turn-phone",
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      payload: :binary.copy(<<1_000::little-signed-16>>, 960),
      reply_to: self()
    }
  end

  defp media_event(binding) do
    %Event{
      kind: :media,
      provider: :twilio,
      provider_event_id: "#{@stream_sid}:2",
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: nil,
      stream_id: @stream_sid,
      sequence_number: 1,
      media: %MediaPacket{
        codec: :pcmu,
        sample_rate: 8_000,
        channels: 1,
        sequence_number: 1,
        timestamp: 0,
        payload: :binary.copy(<<0xFF>>, 160)
      }
    }
  end

  defp media_started_event(binding) do
    %Event{
      kind: :media_started,
      provider: :twilio,
      provider_connection_id: binding.provider_connection_id,
      provider_call_control_id: binding.provider_call_control_id,
      provider_call_leg_id: binding.provider_call_leg_id,
      provider_call_session_id: nil,
      stream_id: @stream_sid
    }
  end

  defp socket(observer) do
    start_supervised!({Task, fn -> socket_loop(observer) end})
  end

  defp socket_loop(observer) do
    receive do
      {:vxpipe_twilio_socket_send, message} ->
        send(observer, {:test_twilio_socket_send, message})
        socket_loop(observer)

      :stop ->
        :ok
    end
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
