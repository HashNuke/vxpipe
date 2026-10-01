defmodule Vxpipe.Providers.ElevenLabs.STTRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, TestCallStartup}
  alias Vxpipe.CallEngine.{TestTenantCredentialSource, TestTransferConnection}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.{AudioFrame, Ingress}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.Speech.Silero
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.STTSession

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    settings = [
      enabled: true,
      wire_module: Wire,
      wire_options: [observer: self()],
      activity_options: [load: fn -> {:ok, :model} end, classify: &classify/3],
      media_ingress: [
        maximum_frames: 50,
        maximum_bytes: 262_144,
        maximum_age_ms: 2_000,
        maximum_consecutive_overflows: 5
      ]
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_text, providers: %{STTSession => settings})
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  test "compiled room keeps manual segments within one caller turn and admits the next turn" do
    plan = plan()
    bindings = %{{plan.tenant_id, "elevenlabs", "default"} => %{"api_key" => "synthetic-key"}}

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               credential_source: {TestTenantCredentialSource, {self(), bindings}}
             )

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    on_exit(fn ->
      try do
        GenServer.stop(authority, :shutdown)
      catch
        :exit, {:noproc, _call} -> :ok
      end
    end)

    caller = attach(plan, room, plan.entry_caller)
    assert_receive {:scribe_started, wire}, 1_000
    _receiver = attach(plan, room, plan.entry_receiver)
    assert {:ok, resources} = Ingress.readiness_resources(caller.media_ingress)
    speech = Enum.find(resources, &(&1.kind == :speech_to_text))

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "scribe-room",
         resources: [speech],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert :ok = Wire.deliver(wire, {:ready, "synthetic-first"})
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    TestCallStartup.await_ready(plan.room_id)

    # Twenty-one seconds of deterministic voiced classification cross the
    # recognizer's segment limit without supplying an acoustic endpoint.
    for sequence <- 1..21 do
      push(plan, room, caller, sequence, :binary.copy(<<1, 0>>, 16_000))
      await_classified(wire)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    assert :ok = Wire.deliver(wire, {:segment, "First segment."})

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      text: "First segment.",
                      final: false,
                      provider_turn_index: 0
                    }},
                   1_000

    refute_receive {:vxpipe_event, %ParticipantTranscription{final: true}}, 50
    push(plan, room, caller, 22, :binary.copy(<<0, 0>>, 9_216))
    assert_receive {:scribe_commit, ^wire}, 1_000
    monitor = Process.monitor(wire)
    assert :ok = Wire.deliver(wire, {:segment, "The same caller turn."})

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      text: "First segment. The same caller turn.",
                      final: true,
                      provider_turn_index: 0
                    }},
                   1_000

    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    push(plan, room, caller, 23, :binary.copy(<<1, 0>>, 2_048))
    assert_receive {:scribe_started, next_wire}, 1_000
    assert :ok = Wire.deliver(next_wire, {:ready, "synthetic-second"})
    assert_receive {:scribe_audio, ^next_wire, _audio}, 1_000
    push(plan, room, caller, 24, :binary.copy(<<0, 0>>, 9_216))
    assert_receive {:scribe_commit, ^next_wire}, 1_000
    assert :ok = Wire.deliver(next_wire, {:segment, "Yes."})

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      text: "Yes.",
                      final: true,
                      provider_turn_index: 1
                    }},
                   1_000
  end

  defp plan do
    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: %{}
    }

    caller =
      Map.put(human, :capabilities, %{
        speech_to_text: %{provider: "elevenlabs", model: "scribe_v2_realtime"}
      })

    assert {:ok, spec} =
             CallSpec.new(
               %{
                 schema_version: CallSpec.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "receiver",
                 defaults: %{capabilities: %{}},
                 media_policy: %{save_transcripts: true},
                 call_variables: %{sections: %{}},
                 participants: %{"caller" => caller, "receiver" => human},
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "scribe-room-spec",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "scribe-room-spec", revision: 1}, transport: %{type: "web"}},
               tenant_id: "scribe-room-tenant",
               actor_id: "scribe-room-actor"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end

  defp attach(plan, room, participant_id) do
    participant = Map.fetch!(plan.participants, participant_id)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "scribe-room-#{participant_id}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} =
             TestTransferConnection.attach(command, nil,
               input_track: %{
                 track_id: "scribe-room-track",
                 codec: :linear16,
                 sample_rate: 16_000,
                 channels: 1
               }
             )

    attachment
  end

  defp push(plan, room, attachment, sequence, audio) do
    participant = Map.fetch!(plan.participants, plan.entry_caller)

    assert :ok =
             CallEngine.push_audio(attachment, %AudioFrame{
               tenant_id: plan.tenant_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "scribe-room-#{plan.entry_caller}",
               track_id: "scribe-room-track",
               codec: :linear16,
               sample_rate: 16_000,
               channels: 1,
               sequence_number: sequence,
               timestamp: sequence * 16_000,
               payload: audio,
               received_at: System.monotonic_time(:millisecond)
             })

    _ = :sys.get_state(attachment.media_ingress)
    assert {:ok, resources} = Ingress.readiness_resources(attachment.media_ingress)
    resource = Enum.find(resources, &(&1.kind == :speech_to_text))
    _ = :sys.get_state(resource.instance)
  end

  defp await_classified(wire) do
    provider = :sys.get_state(wire).owner
    await_classified(provider, System.monotonic_time(:millisecond) + 5_000)
  end

  defp await_classified(provider, deadline) do
    assert System.monotonic_time(:millisecond) < deadline, "classification did not settle"

    case :sys.get_state(provider) do
      %{inference_ref: nil} -> :ok
      _pending -> await_classified(provider, deadline)
    end
  end

  defp classify(_model, %Silero{} = stream, audio) do
    combined = stream.pending <> audio
    count = div(byte_size(combined), 1_024)
    <<complete::binary-size(count * 1_024), pending::binary>> = combined

    probabilities =
      for <<frame::binary-size(1_024) <- complete>>,
        do: if(frame == :binary.copy(<<0>>, 1_024), do: 0.1, else: 0.8)

    {:ok, %Silero{stream | samples: stream.samples + count * 512, pending: pending},
     probabilities}
  end
end
