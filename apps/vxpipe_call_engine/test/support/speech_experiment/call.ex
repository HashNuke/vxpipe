defmodule Vxpipe.CallEngine.SpeechExperiment.Call do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    TestCallStartup,
    TestTransferConnection,
    TestAudioOutputSink,
    TestCallLifecycleTimer
  }

  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Diagnostics.{AgentRuntimeModelProvider, ModelFixture}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSTTSession
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS
  alias Vxpipe.CallEngine.SpeechExperiment.{Recorder, Scope, TTSBridge}

  def start(path, options \\ []) do
    id = "speech-experiment-#{System.unique_integer([:positive, :monotonic])}"
    recorder = start_supervised!({Recorder, observer: self()}, id: {id, :recorder})

    fixture =
      start_supervised!(
        {ModelFixture, name: nil, default_scenario: :success, delay_ms: 0, response: "E"},
        id: {id, :model}
      )

    scope = start_supervised!({Scope, name: via({id, :scope})}, id: {id, :scope})
    configure(path, scope, fixture, recorder, options)
    plan = plan(id, options)

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               call_lifecycle: [
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, timer, 600_000}, 2_000

    sink =
      start_supervised!(
        {TestAudioOutputSink,
         observer: recorder, block_output: Keyword.get(options, :block_output, false)},
        id: {id, :sink}
      )

    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: id <> "-connection",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    connection =
      start_supervised!(
        {TestTransferConnection,
         command: command,
         output: sink,
         observer: recorder,
         input_track: %{track_id: "morse", codec: :linear16, sample_rate: 16_000, channels: 1}},
        id: {id, :connection}
      )

    assert {:ok, attachment} = GenServer.call(connection, :attach)
    TestCallStartup.await_ready(plan.room_id)

    :ok =
      GenServer.call(
        recorder,
        {:bind,
         Map.take(
           command,
           [:tenant_id, :room_id, :incarnation_id, :connection_id]
         )}
      )

    %{
      id: id,
      plan: plan,
      room: room,
      command: command,
      connection: connection,
      attachment: attachment,
      recorder: recorder,
      sink: sink,
      scope: scope,
      timer: timer
    }
  end

  def turn(context, lane, options \\ []) do
    payload = pcm(60)
    <<prefix::binary-size(7_680), tail::binary>> = payload
    :ok = Recorder.begin_turn(context.recorder)
    Keyword.get(options, :after_begin, fn -> :ok end).()

    {admission, lateness} =
      if lane == :paced do
        paced_push(context, payload)
      else
        first = timed_push(context, prefix)
        :ok = Recorder.tail(context.recorder)
        {max(first, timed_push(context, tail)), 0}
      end

    result = Recorder.result(context.recorder)

    %{
      result
      | metrics:
          Map.merge(
            result.metrics,
            %{ingress_admit_max_us: admission, input_lateness_max_us: lateness}
          )
    }
  end

  def push(context, payload) do
    sequence = System.unique_integer([:positive, :monotonic])

    frame =
      struct!(
        AudioFrame,
        Map.take(
          context.command,
          [:tenant_id, :room_id, :incarnation_id, :participant_id, :connection_id]
        )
        |> Map.merge(%{
          track_id: "morse",
          codec: :linear16,
          sample_rate: 16_000,
          channels: 1,
          sequence_number: sequence,
          timestamp: sequence * 320,
          payload: payload,
          received_at: System.monotonic_time(:millisecond)
        })
      )

    assert :ok = CallEngine.push_audio(context.attachment, frame)
  end

  def stop(context) do
    descendants =
      context.scope
      |> DynamicSupervisor.which_children()
      |> Enum.flat_map(fn {_, tree, _, _} ->
        [tree | Enum.map(Supervisor.which_children(tree), &elem(&1, 1))]
      end)
      |> Enum.map(&{&1, Process.monitor(&1)})

    assert {:ok, monitor} =
             CallEngine.monitor_room(
               context.plan.tenant_id,
               context.plan.room_id,
               context.room.incarnation_id
             )

    TestCallLifecycleTimer.fire(context.timer)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000

    for {pid, descendant_monitor} <- descendants do
      assert_receive {:DOWN, ^descendant_monitor, :process, ^pid, _}, 1_000
    end

    Enum.each(
      [:connection, :sink, :model, :recorder, :scope],
      &stop_supervised!({context.id, &1})
    )
  end

  def pcm(unit_ms) do
    samples = div(16_000 * unit_ms, 1_000)

    dot =
      for sample <- 0..(samples - 1), into: <<>> do
        value = round(:math.sin(2 * :math.pi() * 700 * sample / 16_000) * 4_096)
        <<value::little-signed-16>>
      end

    dot <> :binary.copy(<<0, 0>>, samples * 14)
  end

  defp paced_push(context, payload) do
    chunks = for <<chunk::binary-size(640) <- payload>>, do: chunk
    origin = System.monotonic_time(:microsecond)

    measurements =
      for {chunk, index} <- Enum.with_index(chunks, 1) do
        due = origin + index * 20_000
        ref = make_ref()

        Process.send_after(
          self(),
          {:pace, ref},
          max(0, div(due - System.monotonic_time(:microsecond), 1_000))
        )

        receive do
          {:pace, ^ref} -> :ok
        end

        if index == length(chunks), do: Recorder.tail(context.recorder)
        lateness = max(0, System.monotonic_time(:microsecond) - due)
        {timed_push(context, chunk), lateness}
      end

    {measurements |> Enum.map(&elem(&1, 0)) |> Enum.max(),
     measurements |> Enum.map(&elem(&1, 1)) |> Enum.max()}
  end

  defp timed_push(context, payload) do
    started = System.monotonic_time(:microsecond)
    push(context, payload)
    System.monotonic_time(:microsecond) - started
  end

  defp configure(path, scope, fixture, recorder, _options) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    tts =
      if path == :scoped,
        do: {TTSBridge, [scope: scope]},
        else: {MorseCodeTTS.Transport, [emit_interval_ms: 0]}

    tts = {Vxpipe.CallEngine.SpeechExperiment.TTSMeter, [delegate: tts, observer: recorder]}

    settings =
      settings
      |> Keyword.update!(
        :agent_runtime,
        &(&1
          |> Keyword.put(:implementation, :agent_runtime)
          |> Keyword.put(:fixture, {AgentRuntimeModelProvider, [fixture: fixture]}))
      )
      |> Keyword.put(:speech_to_text,
        enabled: false,
        providers: %{
          MorseSTTSession => [
            enabled: true,
            media_ingress: [
              maximum_frames: 100,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )
      |> Keyword.put(:text_to_speech,
        enabled: false,
        providers: %{
          MorseCodeTTS => [
            enabled: true,
            transport: tts,
            maximum_requests: 2
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)
  end

  defp plan(id, options) do
    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"}
    }

    input = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{
        capabilities: %{
          speech_to_text: %{
            provider: "morse",
            model: "morse",
            options: %{sample_rate: 16_000, unit_duration_ms: 60}
          },
          model_inference: %{provider: "fixture", model: "local"},
          text_to_speech: %{
            provider: "morse",
            model: "morse",
            options: %{sample_rate: 16_000, unit_duration_ms: 20}
          }
        }
      },
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human,
        "restrictor" =>
          Map.put(
            human,
            :while_present,
            Keyword.get(options, :restriction, %{transcript_routes: %{}, save_transcripts: false})
          ),
        "assistant" => %{
          type: "agent",
          prompt: "Return E.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 600_000}
    }

    assert {:ok, spec} = CallSpec.new(input, resource_id: id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-experiment",
               actor_id: "actor-experiment",
               call_id: id <> "-call",
               room_id: id
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end

  defp via(key), do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, key}}}
end
