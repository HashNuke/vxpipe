defmodule Vxpipe.CallEngine.OutgoingCallRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, ConnectionAttachment}

  alias Vxpipe.CallEngine.{
    TestCallLifecycleTimer,
    TestOutboundLegConnector,
    TestTransferConnection
  }

  alias Vxpipe.CallEngine.TestSelectiveAgentRuntimeModelProvider
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Telephony.{OutboundLegRequest, OutboundLegRequestResolver}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, runtime)
      |> Keyword.put(:speech_to_speech,
        providers: %{
          Vxpipe.Providers.MorseCode.STSSession => [enabled: true],
          Vxpipe.Providers.MorseCode.DuplexSTSSession => [enabled: true]
        }
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  for model <- ["morse", "morse-duplex"],
      {opening, text} <- [
        {%{mode: "generated"}, "HELLO"},
        {%{mode: "fixed", text: "GOOD DAY"}, "GOOD DAY"}
      ] do
    @opening_model model
    @opening opening
    @opening_text text
    test "native #{@opening_model} STS #{@opening.mode} opening waits for media and produces only agent evidence once" do
      plan =
        plan(
          first_message: @opening,
          capabilities: %{
            speech_to_speech: %{
              provider: "morse",
              model: @opening_model,
              options: %{unit_duration_ms: 20}
            }
          }
        )

      sink = start_supervised!({CallEngine.TestAudioOutputSink, observer: self()})
      assert {:ok, room} = start_call(plan)
      assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
      refute_receive {:test_audio_output, ^sink, _}, 30
      track = %{track_id: "callee-audio", codec: :linear16, sample_rate: 16_000, channels: 1}
      assert {:ok, _attachment} = attach(plan, room, sink, input_track: track)
      output = collect_opening(sink, [])
      {:ok, config} = CallEngine.Provider.MorseCode.Config.new(unit_duration_ms: 20)
      {:ok, decoder} = CallEngine.Provider.MorseCode.Decoder.new(%{config | sample_rate: 48_000})
      assert {:ok, _, decoded} = CallEngine.Provider.MorseCode.Decoder.push(decoder, output)
      assert {:final, @opening_text} in decoded
      played = div(byte_size(output) * 1_000, 48_000 * 2)
      assert :ok = CallEngine.TestAudioOutputSink.playback_progress(sink, played, played)
      assert :ok = CallEngine.TestAudioOutputSink.playback_completed(sink)
      agent = Map.fetch!(plan.participants, plan.entry_receiver).participant_id
      callee = Map.fetch!(plan.participants, plan.entry_caller).participant_id

      assert_receive {:vxpipe_event,
                      %CallEngine.Event.TextOutput{text: @opening_text, participant_id: ^agent}},
                     2_000

      assert {:ok, snapshot} = CallEngine.inspect_live_call(plan.tenant_id, plan.call_id)

      refute Enum.any?(
               snapshot.records,
               &match?(%CallEngine.Archive.Fact{kind: :accepted_input}, &1)
             )

      refute_received {:vxpipe_event,
                       %CallEngine.Event.ParticipantTranscription{participant_id: ^callee}}

      send(authority(plan), {:vxpipe_outbound_leg, request.attempt_id, self(), :answered})
      _ = :sys.get_state(authority(plan))
      refute_receive {:test_audio_output, ^sink, _}, 30
    end
  end

  test "archives bounded dial, answer and end evidence once in local timestamp order" do
    plan = plan(first_message: %{mode: "wait_for_input"})

    assert {:ok, _room} =
             start_call(plan,
               archive: [
                 enabled: true,
                 writer: {CallEngine.TestCollectingArchiveWriter, self()},
                 maximum_pending_facts: 64,
                 retry_delay_ms: 5,
                 drain_timeout_ms: 1_000
               ]
             )

    assert_receive {:test_archive_fact, %CallEngine.Archive.Fact{kind: :room_opened}}, 2_000
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000

    assert_receive {:test_archive_fact,
                    %CallEngine.Archive.Fact{
                      kind: :outgoing_dial_submitted,
                      payload: %{},
                      occurred_at: submitted
                    }},
                   2_000

    owner = authority(plan)
    monitor = Process.monitor(owner)
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), :answered})
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), :answered})

    assert_receive {:test_archive_fact,
                    %CallEngine.Archive.Fact{
                      kind: :outgoing_call_answered,
                      payload: %{"outcome" => "answered"},
                      occurred_at: answered
                    }},
                   2_000

    assert {:ok, snapshot} = CallEngine.inspect_live_call(plan.tenant_id, plan.call_id)

    assert Enum.any?(
             snapshot.records,
             &match?(%CallEngine.Archive.Fact{kind: :outgoing_call_answered}, &1)
           )

    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), {:ended, :hangup}})

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :answered}}},
                   1_000

    assert_receive {:test_archive_fact,
                    %CallEngine.Archive.Fact{
                      kind: :outgoing_dial_ended,
                      payload: %{"outcome" => "answered"},
                      occurred_at: ended
                    }},
                   2_000

    assert DateTime.compare(submitted, answered) in [:lt, :eq]
    assert DateTime.compare(answered, ended) in [:lt, :eq]
    refute_received {:test_archive_fact, %CallEngine.Archive.Fact{kind: :outgoing_call_answered}}
    refute_received {:test_archive_fact, %CallEngine.Archive.Fact{kind: :outgoing_dial_ended}}
  end

  test "durable admission defers handler preparation and exactly one dial" do
    plan = plan()
    reference = make_ref()
    assert {:ok, room} = start_call(plan, outgoing_admission: {self(), reference})

    assert :opening_audio =
             Vxpipe.CallEngine.RoomAuthority.input_admission(plan.tenant_id, plan.room_id)

    assert {:error, :startup_preparing} =
             Vxpipe.CallEngine.RoomAuthority.readiness_binding(authority(plan))

    refute_receive {:test_agent_runtime_model_preparing, _}, 30
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30

    assert {:error, :outgoing_admission_mismatch} =
             CallEngine.admit_outgoing_call(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               make_ref()
             )

    assert {:error, :outgoing_admission_mismatch} =
             CallEngine.admit_outgoing_call(
               plan.tenant_id,
               plan.room_id,
               "other-incarnation",
               reference
             )

    assert :ok =
             CallEngine.admit_outgoing_call(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               reference
             )

    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    assert_receive {:vxpipe_outgoing_submission, ^reference, {:ok, :accepted}}, 1_000

    assert :ok =
             CallEngine.admit_outgoing_call(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               reference
             )

    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
    refute_receive {:vxpipe_outgoing_submission, ^reference, _}, 30
  end

  test "unknown submission is acknowledged before its room disappears" do
    plan = plan()
    reference = make_ref()

    assert {:ok, room} =
             start_call(plan,
               outgoing_admission: {self(), reference},
               submission_status: :unknown
             )

    owner = authority(plan)
    monitor = Process.monitor(owner)

    assert :ok =
             CallEngine.admit_outgoing_call(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               reference
             )

    assert_receive {:vxpipe_outgoing_submission, ^reference, {:ok, :unknown}}, 1_000

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :unknown}}},
                   1_000
  end

  test "loss of the pending admission controller closes the room without dialing" do
    plan = plan()

    controller =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :finish -> :ok
           end
         end}
      )

    assert {:ok, _room} = start_call(plan, outgoing_admission: {controller, make_ref()})
    owner = authority(plan)
    monitor = Process.monitor(owner)
    send(controller, :finish)

    assert_receive {:DOWN, ^monitor, :process, ^owner,
                    {:shutdown, :outgoing_admission_abandoned}},
                   1_000

    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "an authenticated terminal report before the submission return still acknowledges the dial" do
    plan = plan()
    token = make_ref()
    assert {:ok, room} = start_call(plan, outgoing_admission: {self(), token}, block?: true)
    owner = authority(plan)
    monitor = Process.monitor(owner)

    assert :ok =
             CallEngine.admit_outgoing_call(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               token
             )

    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), {:ended, :busy}})
    assert_receive {:vxpipe_outgoing_submission, ^token, {:ok, :accepted}}, 1_000

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :busy}}},
                   1_000
  end

  test "the controller can cancel a pending admission without preparing or dialing" do
    plan = plan()
    token = make_ref()
    assert {:ok, room} = start_call(plan, outgoing_admission: {self(), token})
    monitor = Process.monitor(authority(plan))

    assert :ok =
             CallEngine.cancel_outgoing_admission(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               token
             )

    assert_receive {:DOWN, ^monitor, :process, _, {:shutdown, :outgoing_admission_cancelled}},
                   1_000

    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "only the outgoing callee resolves an initial phone destination" do
    plan = plan()
    callee = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, %{__struct__: OutboundLegRequest, to: "+15550001001", purpose: :initial}} =
             OutboundLegRequestResolver.resolve(plan, callee, "rinc-test")

    assert {:error, :invalid_outbound_destination} =
             OutboundLegRequestResolver.resolve(
               %{plan | direction: :incoming},
               callee,
               "rinc-test"
             )

    assert {:error, :invalid_outbound_destination} =
             OutboundLegRequestResolver.resolve(
               %{plan | entry_caller: "other"},
               callee,
               "rinc-test"
             )
  end

  test "prepares the handler before one dial and opens the default greeting only after callee media" do
    plan = plan(model: "test:blocked")
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_agent_runtime_model_preparing, preparation}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 50
    send(preparation, :release_test_agent_runtime_model)
    assert_receive {:test_outbound_leg_connect, _, request, timeout}, 1_000
    assert request.purpose == :initial
    assert request.room_owner == authority(plan)
    assert request.incarnation_id == room.incarnation_id
    assert timeout > 0 and timeout <= 5_000
    refute_receive {:test_agent_runtime_stream, _, _}, 50

    assert {:ok, %ConnectionAttachment{admission: :main, transfer_attempt_id: nil}} =
             attach(plan, room)

    assert_receive {:test_agent_runtime_stream, _, greeting}, 2_000
    assert List.last(greeting.messages).origin == :engine
    refute_receive {:test_outbound_leg_connect, _, _, _}, 50
  end

  test "one ring deadline ends and disconnects an unanswered call" do
    plan = plan()
    assert {:ok, _room} = start_call(plan)
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    assert_receive {:test_call_lifecycle_timer_scheduled, timer, 5_000}, 1_000
    assert {owner, _, :outgoing_ring} = timer
    monitor = Process.monitor(owner)
    :ok = TestCallLifecycleTimer.fire(timer)
    assert_receive {:test_outbound_leg_disconnect, _, reference}, 1_000
    assert reference == request.participant_id

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :no_answer}}},
                   1_000

    refute_receive {:test_outbound_leg_disconnect, _, _}, 50
    refute_receive {:test_outbound_leg_connect, _, _, _}, 50
  end

  test "a connected callee cancels the deadline and a stale timer cannot end an answered call" do
    plan = plan(first_message: %{mode: "wait_for_input"})
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    assert_receive {:test_call_lifecycle_timer_scheduled, timer, 5_000}, 1_000
    assert {:ok, _} = attach(plan, room)
    assert_receive {:test_call_lifecycle_timer_cancelled, ^timer}, 1_000
    owner = authority(plan)
    monitor = Process.monitor(owner)
    :ok = TestCallLifecycleTimer.fire(timer)
    _ = :sys.get_state(owner)
    refute_receive {:DOWN, ^monitor, :process, _, _}, 50
    refute_receive {:test_agent_runtime_stream, _, _}, 50
  end

  for {reason, outcome} <- [
        busy: :busy,
        no_answer: :no_answer,
        failed: :failed,
        timeout: :no_answer,
        hangup: :rejected,
        machine: :machine
      ] do
    test "normalizes #{reason} before answer and ignores an unrelated attempt" do
      plan = plan()
      assert {:ok, _} = start_call(plan)
      assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
      owner = authority(plan)
      monitor = Process.monitor(owner)
      send(owner, {:vxpipe_outbound_leg, make_ref(), self(), {:ended, unquote(reason)}})
      _ = :sys.get_state(owner)
      refute_receive {:DOWN, ^monitor, :process, _, _}, 10
      send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), {:ended, unquote(reason)}})

      assert_receive {:DOWN, ^monitor, :process, ^owner,
                      {:shutdown, {:outgoing_call, unquote(outcome)}}},
                     1_000

      refute_receive {:test_outbound_leg_connect, _, _, _}, 10
    end
  end

  test "an authenticated answer cancels ringing but still waits for media before the greeting" do
    plan = plan()
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    assert_receive {:test_call_lifecycle_timer_scheduled, timer, 5_000}, 1_000
    owner = authority(plan)
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), :answered})
    assert_receive {:test_call_lifecycle_timer_cancelled, ^timer}, 1_000
    :ok = TestCallLifecycleTimer.fire(timer)
    _ = :sys.get_state(owner)
    refute_receive {:test_agent_runtime_stream, _, _}, 50
    assert {:ok, _} = attach(plan, room)
    assert_receive {:test_agent_runtime_stream, _, _}, 2_000
  end

  test "unknown submission ends without retrying or starting a greeting" do
    plan = plan()
    assert {:ok, room} = start_call(plan, submission_status: :unknown, block?: true)
    assert_receive {:test_outbound_leg_connect, task, _, _}, 1_000
    owner = authority(plan)
    monitor = Process.monitor(owner)
    assert {:ok, _} = attach(plan, room)
    refute_receive {:test_agent_runtime_stream, _, _}, 50
    send(task, :release_test_dial)

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :unknown}}},
                   1_000

    refute_receive {:test_outbound_leg_connect, _, _, _}, 50
  end

  test "a failed submission ends the room with a typed internal failure" do
    plan = plan()
    assert {:ok, _} = start_call(plan, result: :failed, block?: true)
    assert_receive {:test_outbound_leg_connect, task, _, _}, 1_000
    owner = authority(plan)
    monitor = Process.monitor(owner)
    send(task, :release_test_dial)

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :failed}}},
                   1_000
  end

  test "room shutdown cancels a pending submission worker" do
    plan = plan()
    assert {:ok, _} = start_call(plan, block?: true)
    assert_receive {:test_outbound_leg_connect, task, _, _}, 1_000
    monitor = Process.monitor(task)
    owner = authority(plan)
    :ok = GenServer.stop(owner, :shutdown)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 50
  end

  test "a physical answer awaiting machine classification cancels ringing without opening speech" do
    plan = plan()
    assert {:ok, _} = start_call(plan)
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    owner = authority(plan)
    monitor = Process.monitor(owner)
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), :connected})
    assert_receive {:test_call_lifecycle_timer_cancelled, {^owner, _, :outgoing_ring}}, 1_000
    refute_receive {:test_agent_runtime_stream, _, _}, 50
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), {:ended, :machine}})

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :machine}}},
                   1_000
  end

  test "media attached during handler preparation is reconciled when the dial is accepted" do
    plan = plan(model: "test:blocked")
    assert {:ok, room} = start_call(plan)
    assert_receive {:test_agent_runtime_model_preparing, preparation}, 1_000
    assert {:ok, _} = attach(plan, room)
    send(preparation, :release_test_agent_runtime_model)
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    assert_receive {:test_agent_runtime_stream, _, _}, 2_000
    assert_receive {:test_call_lifecycle_timer_cancelled, {_, _, :outgoing_ring}}, 1_000
  end

  test "readiness allows the full configured ring budget after handler preparation" do
    plan = plan(ring_timeout_ms: 60_000)
    assert {:ok, _} = start_call(plan)
    assert_receive {:test_call_lifecycle_timer_scheduled, {_, _, :readiness}, 90_000}, 1_000
    assert_receive {:test_call_lifecycle_timer_scheduled, {_, _, :outgoing_ring}, 60_000}, 1_000
  end

  test "an answer delivered after the absolute ring deadline cannot revive the call" do
    clock = :atomics.new(1, [])
    plan = plan()
    assert {:ok, _} = start_call(plan, [], fn -> :atomics.get(clock, 1) end)
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    owner = authority(plan)
    monitor = Process.monitor(owner)
    :atomics.put(clock, 1, 5_001)
    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), :answered})

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, :no_answer}}},
                   1_000

    refute_receive {:test_agent_runtime_stream, _, _}, 20
  end

  defp start_call(
         plan,
         connector_options \\ [],
         clock \\ fn -> System.monotonic_time(:millisecond) end
       ) do
    {admission, connector_options} = Keyword.pop(connector_options, :outgoing_admission)
    {archive, connector_options} = Keyword.pop(connector_options, :archive, enabled: false)

    CallEngine.start_call(plan,
      outgoing_admission: admission,
      archive: archive,
      outbound_leg_connector:
        {TestOutboundLegConnector,
         Map.new(connector_options) |> Map.merge(%{observer: self(), owner: self()})},
      call_lifecycle: [
        readiness_timeout_ms: 30_000,
        idle_timeout_ms: 15_000,
        outgoing_clock: clock,
        timer: {TestCallLifecycleTimer, [observer: self()]}
      ]
    )
  end

  defp plan(options \\ []) do
    handler = %{
      type: "agent",
      prompt: "Introduce yourself.",
      tools: %{},
      transfers: [],
      capabilities:
        Keyword.get(options, :capabilities, %{
          model_inference: %{
            provider: "fixture",
            model: Keyword.get(options, :model, "test:scripted")
          }
        })
    }

    handler =
      if Keyword.has_key?(options, :first_message),
        do: Map.put(handler, :first_message, Keyword.fetch!(options, :first_message)),
        else: handler

    input = %{
      schema_version: CallSpec.schema_version(),
      outgoing_call: %{
        callee: "customer",
        handled_by: "assistant",
        ring_timeout_ms: Keyword.get(options, :ring_timeout_ms, 5_000)
      },
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      call_variables: %{sections: %{}},
      participants: %{
        "customer" => %{
          type: "human",
          connection: %{service: "phone", mode: "dial", number: "+15550001001"}
        },
        "assistant" => handler
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, spec} = CallSpec.new(input, resource_id: "outgoing-test", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "outgoing-test", revision: 1},
                 transport: %{type: "telephony"},
                 initial_variables: %{}
               },
               tenant_id: "tenant-outgoing",
               actor_id: "actor-outgoing",
               call_id: unique("call"),
               room_id: unique("room")
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end

  defp attach(plan, room, sink \\ nil, options \\ []) do
    callee = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: callee.participant_id,
               connection_id: unique("connection"),
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    TestTransferConnection.attach(command, sink, options)
  end

  defp collect_opening(sink, frames) do
    receive do
      {:test_audio_output, ^sink, frame} ->
        assert frame.sample_rate == 48_000
        collect_opening(sink, [frame.payload | frames])

      {:test_audio_output_finish, ^sink, _turn} ->
        frames |> Enum.reverse() |> IO.iodata_to_binary()
    after
      2_000 -> flunk("native opening did not reach the callee sink")
    end
  end

  defp authority(plan) do
    [{owner, _}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    owner
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
