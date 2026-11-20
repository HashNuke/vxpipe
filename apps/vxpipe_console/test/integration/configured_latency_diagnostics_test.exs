defmodule Vxpipe.Console.Integration.ConfiguredLatencyDiagnosticsTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  @moduletag timeout: 30_000
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, JoinParticipant}

  alias Vxpipe.CallEngine.Diagnostics.{
    AgentRuntimeModelProvider,
    ModelFixture,
    CaptureHandoff,
    SourceWorker,
    SettingsSupervisor,
    RoomService,
    RoomSupervisor
  }

  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Speech.Silero
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Console.Test.SpeechConnection
  alias Vxpipe.Console.Test.DiagnosticsSchedule
  alias Vxpipe.Console.Test.DiagnosticsIngressLatency
  alias Vxpipe.Console.Test.DiagnosticsResponseLatency

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    DiagnosticsSettingsStore,
    LatencyStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentitySession, IdentityUser}
  alias Vxpipe.Providers.ElevenLabs.STTSession

  setup tags do
    parent = self()
    matrix? = Map.get(tags, :matrix, false)
    actual? = Map.get(tags, :actual_inference, false)
    routing? = Map.get(tags, :routing, false)
    enabled = Map.get(tags, :diagnostics_enabled, true)

    measurement_database =
      if Map.get(tags, :external_pcm, false) and
           System.get_env("VXPIPE_DIAGNOSTIC_COMMITTED_WRITES") == "1" do
        Vxpipe.Console.Test.DiagnosticsDatabase.start!()
      else
        if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
        owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
        on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
        nil
      end

    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    model = start_supervised!({ModelFixture, response: "Acknowledged.", delay_ms: 0})

    runtime =
      original
      |> Keyword.update!(
        :agent_runtime,
        &Keyword.put(&1, :fixture, {AgentRuntimeModelProvider, [fixture: model]})
      )
      |> Keyword.put(:diagnostics, port: __MODULE__.Port)
      |> Keyword.put(:speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            wire_module: Wire,
            wire_options: [observer: parent, timed_audio: Map.get(tags, :external_pcm, false)],
            activity_options:
              cond do
                actual? ->
                  [
                    load: actual_loader(parent, :operational),
                    classify: actual_classifier(parent, :operational)
                  ]

                matrix? ->
                  [
                    load: fn -> {:ok, :matrix_model} end,
                    classify: matrix_classifier(parent, :operational)
                  ]

                true ->
                  []
              end,
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )

    runtime =
      if routing? do
        runtime
        |> Keyword.update!(
          :agent_runtime,
          &Keyword.put(
            &1,
            :fixture,
            {CallEngine.TestSelectiveAgentRuntimeModelProvider, [owner: parent]}
          )
        )
        |> Keyword.put(:text_to_speech,
          providers: %{
            Vxpipe.Providers.Deepgram.TTSSession => [
              enabled: true,
              wire_module: CallEngine.TestTextToSpeechTransport,
              wire_options: [
                observer: parent,
                ready_on_start: true,
                start_counter: :atomics.new(1, signed: false),
                block_after_starts: 1
              ],
              maximum_requests: 2
            ]
          }
        )
      else
        runtime
      end

    runtime =
      if Map.get(tags, :mixed_sts, false),
        do:
          Keyword.put(runtime, :speech_to_speech,
            providers: %{Vxpipe.Providers.MorseCode.STSSession => [enabled: true]}
          ),
        else: runtime

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, runtime)

    assert {:ok, %{enabled: ^enabled, revision: settings_revision}} =
             DiagnosticsSettingsStore.update(operator(), enabled, 0)

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         result = DiagnosticsSettingsStore.snapshot()
         send(parent, :settings_read)
         result
       end}
    )

    assert_receive :settings_read
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)

    start_supervised!(
      {Vxpipe.Calls.Diagnostics.Supervisor,
       name: __MODULE__.Diagnostics,
       projection: __MODULE__.Projection,
       repository:
         cond do
           Map.has_key?(tags, :storage_failure) ->
             {Vxpipe.Console.Test.FailingLatencyStore, {parent, tags.storage_failure}}

           matrix? ->
             {LatencyStore, Repo}

           true ->
             {Vxpipe.Console.Test.HeldLatencyStore, {Repo, parent}}
         end,
       writer_supervisor: __MODULE__.Writers,
       collector_supervisor: __MODULE__.Collectors,
       task_supervisor: __MODULE__.Writes,
       maximum_collectors:
         cond do
           Map.get(tags, :external_pcm, false) -> 16
           Map.get(tags, :input_only, false) -> 2
           true -> 1
         end,
       maximum_writers:
         if(Map.get(tags, :repeated_lifecycle, false) or Map.get(tags, :writer_crash, false),
           do: 1,
           else: 64
         ),
       source_options: [
         name: __MODULE__.Sources,
         inference: __MODULE__.Inference,
         tasks: __MODULE__.Tasks,
         runtime: __MODULE__.Runtime,
         port: __MODULE__.Port,
         load:
           cond do
             actual? ->
               actual_loader(parent, :benchmark)

             Map.get(tags, :missing_diagnostic_model, false) ->
               fn ->
                 send(parent, :diagnostic_model_missing)
                 {:error, :missing_model}
               end

             true ->
               &Silero.load/0
           end,
         classify:
           cond do
             actual? ->
               actual_classifier(parent, :benchmark)

             matrix? ->
               benchmark_classifier(parent, Map.get(tags, :diagnostic_failure))

             true ->
               fn model, stream, pcm ->
                 if byte_size(pcm) == 1_024 do
                   Silero.push(stream, model, pcm)
                 else
                   send(parent, {:classify, self(), byte_size(pcm)})

                   receive do
                     :finish -> Silero.push(stream, model, pcm)
                   end
                 end
               end
           end
       ]}
    )

    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    %{
      options: options,
      settings_revision: settings_revision,
      model: model,
      measurement_database: measurement_database
    }
  end

  @tag :connection_ownership
  test "ordinary single-room fixture keeps its established supervised identity", c do
    {_call, connection, _attachment, _wire, _identity} = call(c.options)
    reference = Process.monitor(connection)
    assert :ok = stop_supervised(SpeechConnection)
    assert_receive {:DOWN, ^reference, :process, ^connection, _}
  end

  @tag :trace_oracle
  test "peer transcript projection oracle rejects reordered copies" do
    connection = make_ref()
    first = %{id: "first", connection_id: "source"}
    second = %{id: "second", connection_id: "source"}
    send(self(), {:configured_public_event, connection, second})
    send(self(), {:configured_public_event, connection, first})

    assert_raise ExUnit.AssertionError, fn ->
      assert_peer_projection(connection, "source", [first, second])
    end
  end

  @tag :trace_oracle
  test "stored input oracle rejects rows belonging to another human's canonical turns" do
    events =
      for id <- ["own-first", "own-second"],
          do: struct(CallEngine.Event.ParticipantTurnCompleted, correlation_id: id)

    turns = [%{turn_id: "other-first"}, %{turn_id: "other-second"}]
    assert_raise ExUnit.AssertionError, fn -> assert_stored_input_turns(turns, events) end
  end

  @tag :trace_oracle
  test "single-room trace oracle rejects unexpected events from another room" do
    connection = make_ref()
    send(self(), {:configured_speech_closed, connection})
    send(self(), {:control_trace_agent, connection, "agent"})
    event = struct(CallEngine.Event.ParticipantTurnStarted, room_id: "unexpected-room")
    send(self(), {:configured_public_event, event})

    assert_raise ExUnit.AssertionError, fn ->
      assert_complete_text_trace(connection, %{room_id: "expected-room"}, [])
    end
  end

  for vad <- [false, true], enabled <- [false, true] do
    @tag :integration
    @tag matrix: true,
         actual_inference: true,
         external_pcm: true,
         timeout: 90_000,
         external_case: "#{vad}/#{enabled}",
         vad: vad,
         diagnostics_enabled: enabled
    test "externally paced actual Silero smoke, operational #{vad}, collection #{enabled}", c do
      workload =
        case System.get_env("VXPIPE_DIAGNOSTIC_WORKLOAD", "smoke") do
          "smoke" -> :smoke
          "warm" -> :warm
        end

      plan = DiagnosticsSchedule.profile(workload)
      room_count = String.to_integer(System.get_env("VXPIPE_DIAGNOSTIC_ROOMS", "1"))

      inputs_per_room =
        String.to_integer(System.get_env("VXPIPE_DIAGNOSTIC_INPUTS_PER_ROOM", "1"))

      assert inputs_per_room in 1..2
      assert room_count in 1..16 and room_count * inputs_per_room <= 16

      primary_inputs =
        Enum.map(1..room_count, fn _ ->
          call(c.options, c.vad, {:concurrent_llm, inputs_per_room}, :scoped)
        end)

      calls =
        Enum.flat_map(primary_inputs, fn {_, _, _, _, identity} = primary ->
          if inputs_per_room == 2 do
            room_id = identity.room_id
            assert_receive {:diagnostic_extra_input, ^room_id, extra}
            [primary, extra]
          else
            [primary]
          end
        end)

      total_inputs = room_count * inputs_per_room

      for {call, _, _, _, _} <- calls do
        assert Enum.count(Map.values(call.plan.participants), &(&1.kind == :human)) ==
                 inputs_per_room
      end

      pcm_path = Vxpipe.Providers.Deepgram.LiveFixture.pcm_path()
      generator = Path.expand("../../../../scripts/diagnostics/pcm_generator.py", __DIR__)
      python = System.find_executable("python3")
      assert is_binary(python)

      affinity_args =
        case System.get_env("VXPIPE_DIAGNOSTIC_GENERATOR_CPUS") do
          nil -> []
          value -> ["--cpus", value]
        end

      sample_resources? = System.get_env("VXPIPE_DIAGNOSTIC_RESOURCE_SAMPLES") == "1"
      if workload == :warm, do: assert(sample_resources?)
      resource_args = if sample_resources?, do: ["--measure-pid", System.pid()], else: []

      generator_args =
        [
          generator,
          "--pcm",
          pcm_path,
          "--inputs",
          to_string(total_inputs),
          "--frames",
          to_string(plan.frames),
          "--workload",
          Atom.to_string(workload),
          "--settlement-inputs-per-room",
          to_string(inputs_per_room)
        ] ++
          affinity_args ++ resource_args

      {executable, arguments} =
        if System.get_env("VXPIPE_DIAGNOSTIC_GENERATOR_SYSTEMD") == "1" do
          # A user-manager service starts outside the measured VM's strict CPU
          # cgroup. A direct Port child would inherit that cgroup's CPU limit.
          systemd = System.find_executable("systemd-run")
          assert is_binary(systemd)

          run_id =
            System.get_env("VXPIPE_DIAGNOSTIC_RUN_ID") ||
              String.replace(Ecto.UUID.generate(), "-", "")

          assert Regex.match?(~r/\A[0-9a-f]{32}\z/, run_id)
          unit = "vxpipe-diagnostic-generator-#{run_id}-#{Ecto.UUID.generate()}.service"
          IO.puts("DIAGNOSTIC_GENERATOR_UNIT " <> unit)

          on_exit(fn ->
            # It may already have exited and been collected; stop only our unit.
            System.cmd("systemctl", ["--user", "stop", unit], stderr_to_stdout: true)
            :ok
          end)

          {systemd,
           [
             "--user",
             "--quiet",
             "--pipe",
             "--wait",
             "--collect",
             "--service-type=exec",
             "--property=RuntimeMaxSec=45",
             "--property=TimeoutStopSec=2",
             "--unit=#{unit}",
             "--",
             python
           ] ++ generator_args}
        else
          {python, generator_args}
        end

      response_trace =
        start_supervised!(
          {CallEngine.TestResponseTrace,
           rooms: Enum.map(calls, fn {_, _, attachment, _, _} -> attachment.room_authority end),
           maximum_events:
             2 *
               Enum.sum(
                 for index <- 0..(total_inputs - 1),
                     do:
                       length(
                         DiagnosticsSchedule.settlements(
                           index,
                           room_count,
                           inputs_per_room,
                           workload
                         )
                       )
               )}
        )

      pre_launch_us = System.monotonic_time(:microsecond)

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:packet, 4},
          args: arguments
        ])

      inputs =
        calls
        |> Enum.with_index()
        |> Map.new(fn {{call, connection, attachment, wire, identity}, index} ->
          {index,
           %{
             call: call,
             connection: connection,
             attachment: attachment,
             wire: wire,
             identity: identity,
             epoch: make_ref(),
             frames: 0,
             offered: [],
             ingress_times: %{},
             ingress_latency: [],
             received: [],
             completed: 0,
             expected_frames:
               DiagnosticsSchedule.frame_count(index, room_count, inputs_per_room, workload),
             expected_turns:
               length(
                 DiagnosticsSchedule.settlements(index, room_count, inputs_per_room, workload)
               ),
             settlements: [],
             settlement_times: %{},
             completion_times: %{}
           }}
        end)

      result =
        external_pcm_loop(%{
          port: port,
          rooms: room_count,
          inputs_per_room: inputs_per_room,
          inputs: inputs,
          exited?: false,
          manifest: nil,
          report: nil,
          resources: [],
          workload: workload,
          measurement_started_us: nil,
          wire_indices: Map.new(inputs, fn {index, input} -> {input.wire, index} end),
          source_indices:
            Map.new(inputs, fn {index, input} ->
              {{input.identity.room_id, input.identity.participant_id}, index}
            end)
        })

      for {index, input} <- result.inputs do
        assert input.received == input.offered
        assert input.frames == input.expected_frames

        expected = DiagnosticsSchedule.settlements(index, room_count, inputs_per_room, workload)

        assert Enum.reverse(input.settlements) == expected

        assert Enum.at(result.manifest["provider_settlement_frames"], index) ==
                 Enum.map(expected, &elem(&1, 0))
      end

      assert result.manifest["tail_encoding"] == "silence-outside-speech-windows"
      assert result.manifest["inputs"] == total_inputs
      assert result.manifest["frames_per_input"] == plan.frames
      assert result.manifest["workload_profile"] == Atom.to_string(workload)
      assert result.manifest["duration_ns"] == plan.duration_ns
      assert result.manifest["measurement_start_ns"] == plan.measurement_start_ns

      assert result.manifest["input_frame_counts"] ==
               Enum.map(
                 0..(total_inputs - 1),
                 &DiagnosticsSchedule.frame_count(&1, room_count, inputs_per_room, workload)
               )

      assert result.report["frames_sent"] ==
               Enum.sum(Enum.map(result.inputs, fn {_, input} -> input.expected_frames end))

      if workload == :warm,
        do: assert(result.report["measured_frames_sent"] == 625 * total_inputs)

      IO.puts(
        "DIAGNOSTIC_EXTERNAL_GENERATOR " <>
          Jason.encode!(%{
            operational_vad: c.vad,
            collection: c.diagnostics_enabled,
            manifest: result.manifest,
            report: result.report
          })
      )

      assert result.manifest["fixture_sha256"] ==
               Base.encode16(:crypto.hash(:sha256, File.read!(pcm_path)), case: :lower)

      clip = binary_part(File.read!(pcm_path), 0, plan.speech_frames * 1024)

      assert result.manifest["speech_clip"] == %{
               "offset_samples" => 0,
               "samples" => plan.speech_frames * 512,
               "sha256" => Base.encode16(:crypto.hash(:sha256, clip), case: :lower)
             }

      if sample_resources? do
        interval = result.report["resource_interval"]
        assert interval["timing_valid"] == true
        assert interval["pid"] == String.to_integer(System.pid())
        samples = div(plan.duration_ns - plan.measurement_start_ns + 99_999_999, 100_000_000) + 1
        assert interval["summary"]["sample_count"] == samples
        assert length(result.resources) == samples
        resources = Enum.reverse(result.resources)
        assert hd(resources)["sample"]["interval_start"] == true

        for resource <- resources do
          assert resource["sample"]["pid"] == interval["pid"]
          assert resource["sample"]["start_ticks"] == interval["start_ticks"]
        end
      else
        assert result.resources == []
        assert result.report["resource_interval"] == nil
      end

      room_inputs = result.inputs |> Map.values() |> Enum.uniq_by(& &1.identity.room_id)

      for %{attachment: attachment, identity: identity} <- room_inputs do
        assert {:ok, completion} =
                 CallEngine.monitor_room_completion(
                   identity.tenant_id,
                   identity.room_id,
                   identity.incarnation_id
                 )

        GenServer.stop(attachment.room_authority, :shutdown)
        assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      end

      turn_evidence =
        for {index, input} <- result.inputs, into: %{} do
          %{call: call, connection: connection, wire: wire, identity: identity} = input
          await_diagnostic_drain(identity)

          events =
            assert_complete_text_trace(
              connection,
              identity,
              Enum.map(1..input.expected_turns, &external_turn_text(index, &1)),
              {:source, connection, identity.connection_id}
            )

          peers =
            result.inputs
            |> Map.values()
            |> Enum.filter(
              &(&1.identity.room_id == identity.room_id and &1.connection != connection)
            )

          projected =
            Enum.filter(
              events,
              &(&1.__struct__ in [ParticipantTranscription, CallEngine.Event.TextOutput])
            )

          for peer <- peers,
              do: assert_peer_projection(peer.connection, identity.connection_id, projected)

          assert {:ok, %{entries: runs}} =
                   LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

          if c.diagnostics_enabled do
            assert length(runs) == inputs_per_room

            assert %{run: run} =
                     Enum.find(runs, &(&1.run.participant_id == identity.participant_id))

            assert {:ok, turns} =
                     LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)

            assert_stored_input_turns(turns, events, input.expected_turns)
          else
            assert runs == []
          end

          if System.get_env("VXPIPE_DIAGNOSTIC_COMMITTED_WRITES") == "1" do
            options = c.measurement_database || Repo.config()
            reader_options = Keyword.drop(options, [:name, :pool, :pool_size])

            reader =
              start_supervised!(
                Supervisor.child_spec({Postgrex, reader_options}, id: {:reader, index})
              )

            assert %{rows: [[1]]} =
                     Postgrex.query!(reader, "SELECT count(*) FROM calls WHERE public_id = $1", [
                       Ecto.UUID.dump!(call.id)
                     ])

            expected_rows =
              if c.diagnostics_enabled do
                result.inputs
                |> Map.values()
                |> Enum.filter(&(&1.identity.room_id == identity.room_id))
                |> Enum.map(& &1.expected_turns)
                |> Enum.sum()
              else
                0
              end

            assert %{rows: [[^expected_rows]]} =
                     Postgrex.query!(
                       reader,
                       "SELECT count(*) FROM call_turn_diagnostics d JOIN call_latency_runs r ON r.id = d.run_id JOIN calls c ON c.id = r.call_id WHERE c.public_id = $1",
                       [Ecto.UUID.dump!(call.id)]
                     )
          end

          refute_received {:scribe_audio, ^wire, _}
          refute_received {:scribe_audio, ^wire, _, _, _}
          refute_received {:scribe_commit, ^wire}

          measured =
            if workload == :warm do
              window =
                DiagnosticsSchedule.measurement_window(
                  pre_launch_us,
                  result.measurement_started_us,
                  workload
                )

              completed =
                events
                |> Enum.filter(&match?(%CallEngine.Event.ParticipantTurnCompleted{}, &1))
                |> Enum.with_index(1)

              count =
                Enum.count(completed, fn {event, turn} ->
                  DiagnosticsSchedule.completed_within?(
                    window,
                    Map.fetch!(input.settlement_times, turn),
                    Map.fetch!(input.completion_times, event.correlation_id)
                  )
                end)

              assert count >= 10,
                     "fewer than ten completions proven inside the resource interval for input #{index}"

              count
            end

          canonical =
            events
            |> Enum.filter(&match?(%CallEngine.Event.ParticipantTurnCompleted{}, &1))
            |> Enum.with_index(1)
            |> Enum.map(fn {event, turn} ->
              %{turn: turn, correlation_id: event.correlation_id, command_id: event.command_id}
            end)

          {index, %{measured: measured, turns: canonical}}
        end

      measured_turn_counts =
        Map.new(turn_evidence, fn {index, entry} -> {to_string(index), entry.measured} end)

      canonical_turns = Map.new(turn_evidence, fn {index, entry} -> {index, entry.turns} end)

      sources =
        Map.new(result.inputs, fn {index, input} ->
          {index,
           Map.take(input.identity, [:room_id, :incarnation_id, :participant_id, :connection_id])}
        end)

      assert {:ok, response_events} = CallEngine.TestResponseTrace.snapshot(response_trace)

      response_dispatch = %{
        boundary: "canonical-audio-completion-publication-to-dispatch-invocation-v1",
        sources: sources,
        turns: canonical_turns,
        events: response_events,
        summary:
          DiagnosticsResponseLatency.summarize(
            sources,
            canonical_turns,
            response_events,
            room_count,
            inputs_per_room,
            workload
          )
      }

      stop_supervised!(CallEngine.TestResponseTrace)

      assert_diagnostic_slots_released()
      refute_received {:configured_public_event, _}
      refute_received {:configured_public_event, _, _}

      evidence = actual_inference_evidence()

      readiness =
        if c.vad or c.diagnostics_enabled do
          expected = if c.vad, do: :operational, else: :benchmark

          ready =
            for {index, input} <- result.inputs, into: %{} do
              fingerprints =
                input.offered
                |> Enum.reject(fn pcm ->
                  # The source marker alone is not evidence of speech-bearing PCM.
                  if total_inputs > 1,
                    do: binary_part(pcm, 2, 1022) == :binary.copy(<<0>>, 1022),
                    else: pcm == :binary.copy(<<0>>, 1024)
                end)
                |> MapSet.new(&:crypto.hash(:sha256, &1))

              assert MapSet.size(fingerprints) > 0

              assert Enum.any?(evidence, fn {mode, count, fingerprint, _at} ->
                       mode == expected and count > 0 and
                         MapSet.member?(fingerprints, fingerprint)
                     end),
                     "no actual inference of generated PCM for input #{index}"

              ready_at =
                evidence
                |> Enum.filter(fn {mode, count, fingerprint, _} ->
                  mode == expected and count > 0 and MapSet.member?(fingerprints, fingerprint)
                end)
                |> Enum.map(&elem(&1, 3))
                |> Enum.min()

              if workload == :warm,
                do:
                  assert(
                    ready_at <= pre_launch_us + 5_000_000,
                    "source model missed fixed warm-up readiness"
                  )

              {to_string(index), ready_at}
            end

          assert Enum.all?(evidence, fn {mode, _, _, _} -> mode == expected end)
          ready
        else
          assert evidence == []
          refute_received {:actual_model_load_started, _}
          %{}
        end

      refute_received {:actual_inference_failed, _}
      if c.vad, do: refute_received({:actual_model_load_started, :benchmark})
      refute_received {:vxpipe_connection_unavailable, _}
      assert result.report["timing_valid"]

      ingress_samples =
        Map.new(result.inputs, fn {index, input} ->
          {index, Enum.reverse(input.ingress_latency)}
        end)

      ingress_latency = %{
        boundary: "accepted-push-invocation-to-provider-receipt-v1",
        samples: ingress_samples,
        summary:
          DiagnosticsIngressLatency.summarize(
            ingress_samples,
            room_count,
            inputs_per_room,
            workload
          )
      }

      IO.puts(
        "DIAGNOSTIC_EXTERNAL_SMOKE " <>
          Jason.encode!(%{
            operational_vad: c.vad,
            collection: c.diagnostics_enabled,
            rooms: room_count,
            inputs_per_room: inputs_per_room,
            workload: Atom.to_string(workload),
            measured_turn_counts: measured_turn_counts,
            ingress_latency: ingress_latency,
            response_dispatch: response_dispatch,
            model_ready_at_us: readiness,
            model_ready_by_us:
              if(workload == :warm, do: pre_launch_us + div(plan.measurement_start_ns, 1_000)),
            measurement_window:
              if(workload == :warm,
                do:
                  DiagnosticsSchedule.measurement_window(
                    pre_launch_us,
                    result.measurement_started_us,
                    workload
                  )
              ),
            settlement_schedule:
              "#{plan.cadence}-frame-cadence-#{plan.speech_frames}-frame-speech-windows",
            settlement_frames:
              Map.new(result.inputs, fn {index, input} ->
                {Integer.to_string(index),
                 input.settlements |> Enum.reverse() |> Enum.map(&elem(&1, 0))}
              end),
            persistence: if(c.measurement_database, do: "committed", else: "sandbox"),
            database_pool_size:
              if(c.measurement_database, do: Keyword.fetch!(c.measurement_database, :pool_size)),
            generator:
              Map.take(result.report, [
                "frames_sent",
                "audio_start_ns",
                "measured_frames_sent",
                "p95_lateness_ns",
                "measured_p95_lateness_ns",
                "elapsed_ns",
                "generator_cpu_seconds",
                "resource_interval"
              ])
          })
      )
    end
  end

  test "configured Scribe call persists pending timing then late acoustic confirmation", c do
    {call, _connection, attachment, wire, identity} = call(c.options)
    epoch = make_ref()
    sequence = discover_with_audio(attachment, identity, epoch, wire)
    sample_origin = sequence * 512

    await(fn -> RoomService.status(RoomService.address(identity)).active_sources == 1 end)

    run =
      await(fn ->
        case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
          {:ok, %{entries: [%{run: run}]}} -> run
          _ -> nil
        end
      end)

    assert run.profile.model == "scribe_v2_realtime"
    pcm = File.read!(Vxpipe.Providers.Deepgram.LiveFixture.pcm_path())

    <<first::binary-size(32_000), second::binary-size(32_000), third::binary-size(32_000),
      _::binary>> = pcm

    for {chunk, index} <- [{first, 0}, {second, 1}] do
      pace(1_000)

      send_audio(
        attachment,
        identity,
        epoch,
        sequence + index,
        sample_origin + 16_000 * index,
        chunk
      )

      assert_receive {:classify, task, 32_000}, 5_000
      monitor = Process.monitor(task)
      send(task, :finish)
      assert_receive {:DOWN, ^monitor, :process, ^task, :normal}, 2_000
    end

    pace(1_000)
    send_audio(attachment, identity, epoch, sequence + 2, sample_origin + 32_000, third)
    assert_receive {:classify, task, 32_000}, 2_000

    for {kind, text} <- [
          {"partial_transcript", "The final word is telescope."},
          {"committed_transcript", "The final word is telescope."},
          {"partial_transcript", ""}
        ] do
      :ok = Wire.deliver_frame(wire, JSON.encode!(%{"message_type" => kind, "text" => text}))
    end

    assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = transcript}, 1_000

    pending =
      await(
        fn ->
          case LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil) do
            {:ok, [turn]} -> turn
            _ -> nil
          end
        end,
        500
      )

    assert pending.turn_id == transcript.correlation_id
    assert pending.landmarks_us[:observer_confirmed] == nil
    monitor = Process.monitor(task)
    send(task, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^task, :normal}, 2_000
    pace(8)

    send_audio(
      attachment,
      identity,
      epoch,
      sequence + 3,
      sample_origin + 48_000,
      <<0::size(2048)>>
    )

    assert_receive {:classify, tail_task, 256}, 2_000
    tail_monitor = Process.monitor(tail_task)
    send(tail_task, :finish)
    assert_receive {:DOWN, ^tail_monitor, :process, ^tail_task, :normal}, 2_000

    revised =
      await(fn ->
        {:ok, turns} = LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)

        Enum.find(
          turns,
          &(&1.revision > pending.revision and is_integer(&1.landmarks_us[:observer_confirmed]))
        )
      end)

    assert revised.landmarks_us.provider_end_received <= revised.landmarks_us.observer_confirmed
    assert revised.acoustic_reason == :partial_start

    # A second complete turn establishes normal coverage after the prospective first turn.
    for {chunk, index} <- [{first, 0}, {second, 1}, {third, 2}] do
      pace(1_000)

      send_audio(
        attachment,
        identity,
        epoch,
        sequence + 4 + index,
        sample_origin + 48_128 + 16_000 * index,
        chunk
      )

      assert_receive {:classify, next_task, 32_000}, 2_000
      next_monitor = Process.monitor(next_task)
      send(next_task, :finish)
      assert_receive {:DOWN, ^next_monitor, :process, ^next_task, :normal}, 2_000
    end

    for {kind, text} <- [
          {"partial_transcript", "Please repeat the answer."},
          {"committed_transcript", "Please repeat the answer."},
          {"partial_transcript", ""}
        ] do
      :ok = Wire.deliver_frame(wire, JSON.encode!(%{"message_type" => kind, "text" => text}))
    end

    assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = second_transcript},
                   1_000

    pace(8)

    send_audio(
      attachment,
      identity,
      epoch,
      sequence + 7,
      sample_origin + 96_128,
      <<0::size(2048)>>
    )

    assert_receive {:classify, last_task, 256}, 2_000
    last_monitor = Process.monitor(last_task)
    send(last_task, :finish)
    assert_receive {:DOWN, ^last_monitor, :process, ^last_task, :normal}, 2_000

    available =
      await(fn ->
        {:ok, turns} = LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)

        Enum.find(
          turns,
          &(&1.turn_id == second_transcript.correlation_id and &1.quality == :available and
              is_integer(&1.landmarks_us[:first_response_text]))
        )
      end)

    assert available.acoustic_reason == nil
    assert is_integer(available.durations_us.room_to_first_text)
    assert available.durations_us.room_to_first_text >= 0
    assert is_integer(available.durations_us.speech_end_to_provider_end)
    assert available.durations_us.speech_end_to_provider_end >= 0
    assert available.turn_id != revised.turn_id

    collector =
      case DynamicSupervisor.which_children(__MODULE__.Collectors) do
        [{_, pid, _, _}] -> pid
      end

    [{_, writer, _, _}] = DynamicSupervisor.which_children(__MODULE__.Writers)
    writer_monitor = Process.monitor(writer)
    collector_monitor = Process.monitor(collector)
    room_monitor = Process.monitor(attachment.room_authority)
    GenServer.stop(attachment.room_authority, :shutdown)
    assert_receive {:DOWN, ^room_monitor, :process, _, :shutdown}, 1_000
    assert_receive {:terminal_diagnostic_write, write_task, run_id}, 1_000
    assert run_id == run.id
    assert_receive {:DOWN, ^collector_monitor, :process, ^collector, :normal}, 1_000

    assert {:ok, %{state: :running, closed_at: nil}} =
             LatencyStore.fetch_run(Repo, call.tenant_key, call.id, run.id)

    refute_received {:DOWN, ^writer_monitor, :process, ^writer, _}
    send(write_task, :persist_terminal)
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :normal}, 2_000

    closed =
      await(fn ->
        case LatencyStore.fetch_run(Repo, call.tenant_key, call.id, run.id) do
          {:ok, %{closed_at: %DateTime{}} = stored} -> stored
          _ -> nil
        end
      end)

    assert closed.counts.observed_turns == 2

    assert {:ok, stored} =
             LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)

    assert Enum.any?(stored, &(&1.turn_id == revised.turn_id and &1.revision >= revised.revision))
    assert Enum.any?(stored, &(&1.turn_id == available.turn_id and &1.quality == :available))
  end

  for vad <- [false, true], diagnostics <- [false, true] do
    @tag matrix: true, diagnostics_enabled: diagnostics
    @vad vad
    @diagnostics diagnostics
    @expected if(vad, do: :operational, else: if(diagnostics, do: :benchmark, else: nil))
    test "configured source uses the correct inference path with VAD #{@vad} and diagnostics #{@diagnostics}",
         c do
      {call, _connection, attachment, wire, identity} = call(c.options, @vad)
      epoch = make_ref()

      sequence =
        if @diagnostics do
          discover_with_audio(attachment, identity, epoch, wire)
        else
          send_audio(attachment, identity, epoch, 0, 0, <<0::size(8192)>>)
          assert_receive {:scribe_audio, ^wire, _}, 2_000
          _ = RoomService.scan(RoomService.address(identity))
          assert RoomService.status(RoomService.address(identity)).active_sources == 0
          1
        end

      pcm = :binary.copy(<<7, 0>>, 512)
      send_audio(attachment, identity, epoch, sequence, sequence * 512, pcm)
      assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000

      expected = @expected

      if expected do
        assert_receive {:matrix_inference, ^expected, samples, ^pcm}, 2_000
        if @vad, do: assert(samples == sequence * 512)
      end

      if @diagnostics do
        run =
          await(fn ->
            case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
              {:ok, %{entries: [%{run: run}]}} -> run
              _ -> nil
            end
          end)

        assert run.profile.inference_source ==
                 if(@vad, do: :operational_reuse, else: :benchmark_only)
      else
        assert {:ok, %{entries: []}} =
                 LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

        assert DynamicSupervisor.count_children(RoomSupervisor.address(identity, :workers)).active ==
                 0
      end

      assert {:ok, %{entries: before_toggle}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      off_pcm = :binary.copy(<<8, 0>>, 512)

      next_sequence =
        if @diagnostics do
          change_diagnostics(false, c.settings_revision)
          _ = RoomService.scan(RoomService.address(identity))
          await_diagnostic_drain(identity)
          send_audio(attachment, identity, epoch, sequence + 1, (sequence + 1) * 512, off_pcm)
          assert_receive {:scribe_audio, ^wire, ^off_pcm}, 2_000

          if @vad do
            assert_receive {:matrix_inference, :operational, samples, ^off_pcm}, 2_000
            assert samples == (sequence + 1) * 512
          end

          sequence + 2
        else
          sequence + 1
        end

      change_diagnostics(
        true,
        if(@diagnostics, do: c.settings_revision + 1, else: c.settings_revision)
      )

      next_sequence = discover_with_audio(attachment, identity, epoch, wire, next_sequence)
      on_pcm = :binary.copy(<<9, 0>>, 512)
      send_audio(attachment, identity, epoch, next_sequence, next_sequence * 512, on_pcm)
      assert_receive {:scribe_audio, ^wire, ^on_pcm}, 2_000
      enabled_mode = if @vad, do: :operational, else: :benchmark
      assert_receive {:matrix_inference, ^enabled_mode, samples, ^on_pcm}, 2_000
      if @vad, do: assert(samples == next_sequence * 512)

      entries =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: entries}} when length(entries) == length(before_toggle) + 1 ->
              entries

            _ ->
              nil
          end
        end)

      assert length(Enum.uniq_by(entries, & &1.run.source_epoch)) == length(entries)

      assert Enum.all?(before_toggle, fn old -> Enum.any?(entries, &(&1.run.id == old.run.id)) end)

      replacement_epoch = make_ref()
      replacement_probe = :binary.copy(<<10, 0>>, 512)
      send_audio(attachment, identity, replacement_epoch, 0, 0, replacement_probe)
      assert_receive {:scribe_audio, ^wire, ^replacement_probe}, 2_000

      if @vad do
        assert_receive {:matrix_inference, :operational, samples, ^replacement_probe}, 2_000
        assert samples == (next_sequence + 1) * 512
      end

      _ = RoomService.scan(RoomService.address(identity))
      await_diagnostic_drain(identity)

      replacement_sequence = discover_with_audio(attachment, identity, replacement_epoch, wire, 1)
      replacement_pcm = :binary.copy(<<11, 0>>, 512)

      send_audio(
        attachment,
        identity,
        replacement_epoch,
        replacement_sequence,
        replacement_sequence * 512,
        replacement_pcm
      )

      assert_receive {:scribe_audio, ^wire, ^replacement_pcm}, 2_000
      assert_receive {:matrix_inference, ^enabled_mode, samples, ^replacement_pcm}, 2_000
      if @vad, do: assert(samples == (next_sequence + 1 + replacement_sequence) * 512)

      replacement_entries =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: rows}} when length(rows) == length(entries) + 1 -> rows
            _ -> nil
          end
        end)

      assert length(Enum.uniq_by(replacement_entries, & &1.run.source_epoch)) ==
               length(replacement_entries)

      assert Enum.all?(entries, fn old ->
               Enum.any?(
                 replacement_entries,
                 &(&1.run.id == old.run.id and not is_nil(&1.run.closed_at))
               )
             end)

      GenServer.stop(attachment.room_authority, :shutdown)
      await_diagnostic_drain(identity)

      refute_received {:matrix_inference, _, _, ^replacement_probe}
      refute_received {:matrix_inference, _, _, ^replacement_pcm}
      refute_received {:scribe_audio, ^wire, ^replacement_probe}
      refute_received {:scribe_audio, ^wire, ^replacement_pcm}
      refute_received {:matrix_inference, _, _, ^pcm}
      refute_received {:matrix_inference, _, _, ^off_pcm}
      refute_received {:matrix_inference, _, _, ^on_pcm}
      refute_received {:scribe_audio, ^wire, ^pcm}
      refute_received {:scribe_audio, ^wire, ^off_pcm}
      refute_received {:scribe_audio, ^wire, ^on_pcm}
      refute_received {:scribe_commit, ^wire}
    end
  end

  for vad <- [false, true] do
    @tag matrix: true, vad: vad, settings_unavailable: true
    test "settings store unavailability revokes and recovers configured observation, Silero #{vad}",
         c do
      {call, _connection, attachment, wire, identity} = call(c.options, c.vad)
      epoch = make_ref()
      sequence = discover_with_audio(attachment, identity, epoch, wire)
      before = lifecycle_turn(c, call, attachment, wire, identity, epoch, sequence, 81, :enabled)

      [{_, worker, _, _}] =
        DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers))

      handoff = SourceWorker.handoff(worker)
      worker_down = Process.monitor(worker)
      settings = Repo.get!(Vxpipe.Persistence.Schema.DiagnosticsSettings, "default")

      # A real store error, isolated to this sandbox. Do not send an invalidation:
      # the normal projection reader must discover the unavailable setting.
      Repo.delete!(settings)
      assert {:error, :unavailable} = DiagnosticsSettingsStore.snapshot()

      await(fn ->
        match?(
          {:unavailable, _},
          Vxpipe.CallEngine.Diagnostics.SettingsProjection.status(__MODULE__.Projection)
        )
      end)

      assert_receive {:DOWN, ^worker_down, :process, ^worker, _}, 2_000
      await_diagnostic_drain(identity)
      assert_diagnostic_slots_released()
      refute CaptureHandoff.current?(handoff)

      during =
        lifecycle_turn(c, call, attachment, wire, identity, epoch, sequence + 1, 81, :disabled)

      # Recovery at the same durable revision must still mint a fresh capture
      # epoch; the previously revoked handoff cannot become usable again.
      Repo.insert!(Ecto.put_meta(settings, state: :built))

      await(fn ->
        Vxpipe.CallEngine.Diagnostics.SettingsProjection.status(__MODULE__.Projection) ==
          {:enabled, settings.revision}
      end)

      sequence = discover_with_audio(attachment, identity, epoch, wire, sequence + 2)

      recovered =
        lifecycle_turn(c, call, attachment, wire, identity, epoch, sequence, 81, :reenabled)

      assert recovered.run.settings_revision == before.run.settings_revision
      refute recovered.run.id == before.run.id
      refute recovered.run.source_epoch == before.run.source_epoch
      refute CaptureHandoff.current?(handoff)

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)
      assert_diagnostic_slots_released()

      assert {:ok, %{entries: entries}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      assert length(entries) == 2
      %{run: interrupted} = Enum.find(entries, &(&1.run.id == before.run.id))
      assert interrupted.state == :incomplete
      assert :lease_expired in interrupted.reasons

      stored =
        Enum.flat_map(entries, fn %{run: run} ->
          assert run.closed_at != nil

          assert {:ok, turns} =
                   LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)

          Enum.map(turns, &{run.id, &1.turn_id})
        end)

      assert Enum.sort(stored) ==
               Enum.sort([{before.run.id, before.turn_id}, {recovered.run.id, recovered.turn_id}])

      refute Enum.any?(stored, fn {_, turn_id} -> turn_id == during.turn_id end)

      for observed <- [before, during, recovered] do
        pcm = observed.pcm
        turn_id = observed.turn_id
        refute_received {:scribe_audio, ^wire, ^pcm}
        refute_received {:matrix_inference, _, _, ^pcm}

        refute_received {:vxpipe_event,
                         %ParticipantTranscription{final: true, correlation_id: ^turn_id}}

        refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{correlation_id: ^turn_id}}
      end

      refute_received {:scribe_commit, ^wire}
      refute_received {:vxpipe_connection_unavailable, _}
    end
  end

  for vad <- [false, true], enabled <- [false, true] do
    @tag matrix: true, vad: vad, diagnostics_enabled: enabled, writer_crash: true
    test "writer death preserves the configured call and exposes interrupted coverage, Silero #{vad}, collection #{enabled}",
         c do
      {call, connection, attachment, wire, identity} = call(c.options, c.vad, :llm, true)
      epoch = make_ref()

      sequence =
        if c.diagnostics_enabled,
          do: discover_with_audio(attachment, identity, epoch, wire),
          else: 0

      before = writer_failure_turn(c, attachment, wire, identity, epoch, sequence, 71)

      original =
        if c.diagnostics_enabled, do: await(fn -> diagnostic_turn(call, before.turn_id) end)

      if c.diagnostics_enabled do
        [{_, writer, _, _}] = DynamicSupervisor.which_children(__MODULE__.Writers)
        [{_, collector, _, _}] = DynamicSupervisor.which_children(__MODULE__.Collectors)

        [{_, worker, _, _}] =
          DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers))

        monitors = Enum.map([writer, collector, worker], &{&1, Process.monitor(&1)})
        handoff = Vxpipe.Calls.Diagnostics.Writer.handoff(writer)

        # Finish shared sandbox queries before killing the writer. Killing a borrower
        # mid-query disconnects the test's shared transaction, unlike production's
        # independent connections. The writer unit test covers blocked-task death.
        :ok = :sys.suspend(collector)

        try do
          await(fn -> Vxpipe.Calls.Diagnostics.Handoff.stats(handoff).pending_count == 0 end)
          Process.exit(writer, :kill)
        after
          resume_diagnostic_worker(collector)
        end

        for {pid, monitor} <- monitors do
          assert_receive {:DOWN, ^monitor, :process, ^pid, reason}, 2_000
          if pid == writer, do: assert(reason == :killed)
        end
      else
        assert DynamicSupervisor.count_children(__MODULE__.Writers).active == 0
      end

      # Call input and response do not wait for replacement diagnostic attachment.
      during = writer_failure_turn(c, attachment, wire, identity, epoch, sequence + 1, 72)

      next =
        if c.diagnostics_enabled,
          do: discover_with_audio(attachment, identity, epoch, wire, sequence + 2),
          else: sequence + 2

      after_crash = writer_failure_turn(c, attachment, wire, identity, epoch, next, 73)

      if c.diagnostics_enabled do
        recovered = await(fn -> diagnostic_turn(call, after_crash.turn_id) end)
        refute recovered.run_id == original.run_id
        assert DynamicSupervisor.count_children(__MODULE__.Writers).active == 1
      end

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)
      assert_diagnostic_slots_released()

      if c.diagnostics_enabled do
        assert {:ok, access} =
                 Calls.operator_call_access(
                   Vxpipe.Calls.InstallationOperator.authority(),
                   call.tenant_key
                 )

        options = [latency_repository: {LatencyStore, Repo}]

        interrupted =
          await(
            fn ->
              assert {:ok, report} = Calls.fetch_latency_report(access, call.id, options)

              Enum.find(report.entries, fn entry ->
                entry.run.id == original.run_id and entry.coverage.status == :unconfirmed
              end)
            end,
            7_000
          )

        assert :stale_heartbeat in interrupted.coverage.reasons
        assert interrupted.run.state == :running
        assert interrupted.run.closed_at == nil

        assert {:ok, old_turns} =
                 Calls.fetch_latency_turns(access, call.id, original.run_id, options)

        assert Enum.map(old_turns.entries, & &1.turn_id) == [before.turn_id]
      else
        assert {:ok, %{entries: []}} =
                 LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)
      end

      for observed <- [before, during, after_crash] do
        pcm = observed.pcm
        turn_id = observed.turn_id

        if c.diagnostics_enabled and not c.vad and observed == during do
          receive do
            {:matrix_inference, :benchmark, _, ^pcm} -> :ok
          after
            0 -> :ok
          end
        end

        refute_received {:scribe_audio, ^wire, ^pcm}
        refute_received {:matrix_inference, _, _, ^pcm}

        refute_received {:vxpipe_event,
                         %ParticipantTranscription{final: true, correlation_id: ^turn_id}}

        refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{correlation_id: ^turn_id}}
      end

      refute_received {:scribe_commit, ^wire}
      refute_received {:vxpipe_connection_unavailable, _}

      assert_complete_text_trace(connection, identity, [
        "Writer failure turn 71.",
        "Writer failure turn 72.",
        "Writer failure turn 73."
      ])
    end
  end

  for vad <- [false, true], enabled <- [false, true], samples <- [512, 4_096] do
    @tag matrix: true,
         vad: vad,
         diagnostics_enabled: enabled,
         saturation: true,
         frame_samples: samples
    test "full diagnostic queue preserves calls with Silero #{vad}, collection #{enabled}, #{samples} samples",
         c do
      {call, connection, attachment, wire, identity} = call(c.options, c.vad, :llm, true)
      epoch = make_ref()

      sequence =
        if c.diagnostics_enabled,
          do: discover_with_audio(attachment, identity, epoch, wire),
          else: 0

      warmup = :binary.copy(<<230, 0>>, 512)
      send_audio(attachment, identity, epoch, sequence, sequence * 512, warmup)
      assert_receive {:scribe_audio, ^wire, ^warmup}, 2_000
      if c.vad, do: assert_receive({:matrix_inference, :operational, _, ^warmup}, 2_000)

      held =
        if c.diagnostics_enabled do
          [{_, worker, _, _}] =
            DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers))

          handoff = SourceWorker.handoff(worker)
          await(fn -> CaptureHandoff.stats(handoff).pending_count == 0 end)
          assert :ok = :sys.suspend(worker)
          on_exit(fn -> resume_diagnostic_worker(worker) end)
          {worker, handoff, Process.monitor(worker)}
        end

      {queue_samples, first_overflow} =
        Enum.map_reduce(1..96, nil, fn index, first_overflow ->
          pcm = :binary.copy(<<index, 0>>, c.frame_samples)

          send_audio(
            attachment,
            identity,
            epoch,
            sequence + index,
            (sequence + 1) * 512 + (index - 1) * c.frame_samples,
            pcm
          )

          assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
          if c.vad, do: assert_receive({:matrix_inference, :operational, _, ^pcm}, 2_000)

          case held do
            {worker, handoff, _} ->
              stats = assert_saturated_worker_bounds(worker, handoff)
              {stats, first_overflow || if(stats.overflow > 0, do: stats)}

            nil ->
              {nil, first_overflow}
          end
        end)

      if held do
        {worker, handoff, _} = held
        assert first_overflow != nil
        assert assert_saturated_worker_bounds(worker, handoff).overflow > 0

        if c.frame_samples == 512 do
          assert first_overflow.pending_count == handoff.maximum_count
        else
          assert first_overflow.pending_count < handoff.maximum_count
          assert first_overflow.pending_bytes > handoff.maximum_bytes - 16_384
        end
      end

      for index <- 1..2 do
        text = "Continue during queue saturation #{index}."
        emit_scribe_turn(wire, text)
        assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000
        assert input.text == text
        assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
        assert output.text == "Acknowledged."
        assert output.correlation_id == input.correlation_id
        turn_id = input.correlation_id

        assert_receive {:vxpipe_event,
                        %CallEngine.Event.AgentTurnCompleted{correlation_id: ^turn_id}},
                       2_000
      end

      if held do
        {worker, handoff, monitor} = held
        final_sample = assert_saturated_worker_bounds(worker, handoff)

        if System.get_env("VXPIPE_DIAGNOSTIC_STRESS_REPORT") == "1" do
          samples = [final_sample | queue_samples]

          IO.puts(
            "DIAGNOSTIC_STRESS_QUEUE " <>
              Jason.encode!(%{
                operational_vad: c.vad,
                frame_samples: c.frame_samples,
                sample_count: length(samples),
                maximum_pending_count: Enum.max(Enum.map(samples, & &1.pending_count)),
                maximum_pending_bytes: Enum.max(Enum.map(samples, & &1.pending_bytes)),
                maximum_mailbox_count: Enum.max(Enum.map(samples, & &1.mailbox_count)),
                count_limit: handoff.maximum_count,
                byte_limit: handoff.maximum_bytes,
                mailbox_limit: handoff.maximum_count + 8
              })
          )
        end

        change_diagnostics(false, c.settings_revision)
        refute CaptureHandoff.current?(handoff)
        assert :ok = :sys.resume(worker)
        assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
        await_diagnostic_drain(identity)

        assert %{pending_count: 0, pending_bytes: 0, discarded: discarded} =
                 CaptureHandoff.stats(handoff)

        assert discarded > 0
      end

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)
      assert_diagnostic_slots_released()

      assert {:ok, %{entries: entries}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      if c.diagnostics_enabled do
        assert [%{run: run}] = entries
        assert run.state == :incomplete
        assert :observer_overloaded in run.reasons
      else
        assert entries == []
      end

      for index <- 1..96 do
        pcm = :binary.copy(<<index, 0>>, c.frame_samples)
        refute_received {:scribe_audio, ^wire, ^pcm}
        refute_received {:matrix_inference, _, _, ^pcm}
      end

      refute_received {:scribe_commit, ^wire}
      refute_received {:vxpipe_connection_unavailable, _}

      assert_complete_text_trace(
        connection,
        identity,
        Enum.map(1..2, &"Continue during queue saturation #{&1}.")
      )
    end
  end

  for vad <- [false, true] do
    @tag matrix: true, vad: vad, repeated_lifecycle: true, timeout: 120_000
    test "twenty configured enable/revoke/re-enable/teardown cycles release diagnostics, Silero #{vad}",
         c do
      measure_memory? = System.get_env("VXPIPE_DIAGNOSTIC_STRESS_RSS") == "1"

      {rss_samples, _revision} =
        Enum.map_reduce(1..20, c.settings_revision, fn cycle, revision ->
          {call, connection, attachment, wire, identity} = call(c.options, c.vad, :llm, true)
          epoch = make_ref()
          sequence = discover_with_audio(attachment, identity, epoch, wire)

          first =
            lifecycle_turn(c, call, attachment, wire, identity, epoch, sequence, cycle, :enabled)

          assert first.run.settings_revision == revision

          change_diagnostics(false, revision)
          await_diagnostic_drain(identity)
          assert_diagnostic_slots_released()

          disabled =
            lifecycle_turn(
              c,
              call,
              attachment,
              wire,
              identity,
              epoch,
              sequence + 1,
              cycle,
              :disabled
            )

          change_diagnostics(true, revision + 1)
          sequence = discover_with_audio(attachment, identity, epoch, wire, sequence + 2)

          second =
            lifecycle_turn(
              c,
              call,
              attachment,
              wire,
              identity,
              epoch,
              sequence,
              cycle,
              :reenabled
            )

          assert second.run.settings_revision == revision + 2
          refute second.run.id == first.run.id
          refute second.run.source_epoch == first.run.source_epoch

          assert {:ok, completion} =
                   CallEngine.monitor_room_completion(
                     identity.tenant_id,
                     identity.room_id,
                     identity.incarnation_id
                   )

          room_diagnostics = GenServer.whereis(RoomSupervisor.address(identity, :supervisor))
          assert is_pid(room_diagnostics)
          diagnostics_down = Process.monitor(room_diagnostics)
          GenServer.stop(attachment.room_authority, :shutdown)
          assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
          assert_receive {:DOWN, ^diagnostics_down, :process, ^room_diagnostics, _}, 2_000
          await_diagnostic_drain(identity)
          assert_diagnostic_slots_released()

          assert_complete_text_trace(connection, identity, [
            "Lifecycle #{cycle} enabled.",
            "Lifecycle #{cycle} disabled.",
            "Lifecycle #{cycle} reenabled."
          ])

          assert :ok = stop_supervised(SpeechConnection)

          assert {:ok, %{entries: entries}} =
                   LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

          assert length(entries) == 2
          assert Enum.all?(entries, &(not is_nil(&1.run.closed_at)))

          stored =
            Enum.flat_map(entries, fn %{run: run} ->
              assert {:ok, turns} =
                       LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)

              Enum.map(turns, &{run.id, &1.turn_id})
            end)

          assert Enum.sort(stored) ==
                   Enum.sort([
                     {first.run.id, first.turn_id},
                     {second.run.id, second.turn_id}
                   ])

          refute Enum.any?(stored, fn {_, turn_id} -> turn_id == disabled.turn_id end)

          for observed <- [first, disabled, second] do
            pcm = observed.pcm
            turn_id = observed.turn_id
            refute_received {:scribe_audio, ^wire, ^pcm}
            refute_received {:matrix_inference, _, _, ^pcm}

            refute_received {:vxpipe_event,
                             %ParticipantTranscription{final: true, correlation_id: ^turn_id}}

            refute_received {:vxpipe_event,
                             %CallEngine.Event.TextOutput{correlation_id: ^turn_id}}
          end

          refute_received {:scribe_commit, ^wire}
          refute_received {:vxpipe_connection_unavailable, _}
          rss = if measure_memory?, do: diagnostic_rss_kib()
          {rss, revision + 2}
        end)

      if measure_memory? do
        first = rss_samples |> Enum.take(5) |> Enum.sort() |> Enum.at(2)
        last = rss_samples |> Enum.take(-5) |> Enum.sort() |> Enum.at(2)

        IO.puts(
          "DIAGNOSTIC_STRESS_RSS " <>
            Jason.encode!(%{
              operational_vad: c.vad,
              rss_kib: rss_samples,
              first_five_median_kib: first,
              last_five_median_kib: last,
              growth_kib: last - first,
              budget_kib: 16 * 1024
            })
        )

        assert last - first <= 16 * 1024
      end
    end
  end

  for failure <- [:crash, :hang], enabled <- [false, true] do
    @tag matrix: true, diagnostics_enabled: enabled, diagnostic_failure: failure
    @failure failure
    @enabled enabled
    test "configured call continues with diagnostic #{@failure} and enabled #{@enabled}", c do
      {_call, connection, attachment, wire, identity} = call(c.options, false, :llm, true)
      epoch = make_ref()

      sequence =
        if @enabled do
          discover_with_audio(attachment, identity, epoch, wire)
        else
          0
        end

      pcm = :binary.copy(<<9, 0>>, 512)
      send_audio(attachment, identity, epoch, sequence, sequence * 512, pcm)
      assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000

      inference =
        if @enabled do
          failure = @failure
          assert_receive {:diagnostic_failure_started, ^failure, task}, 2_000
          {task, Process.monitor(task)}
        end

      # Identical provider bytes and turn/output behavior with collection off,
      # inference crashed, or inference still blocked on its first frame.
      for index <- 1..2 do
        text = "Continue the call #{index}."
        emit_scribe_turn(wire, text)
        assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000
        assert input.text == text
        assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
        assert output.text == "Acknowledged."
        assert output.correlation_id == input.correlation_id
        turn_id = input.correlation_id

        assert_receive {:vxpipe_event,
                        %CallEngine.Event.AgentTurnCompleted{correlation_id: ^turn_id}},
                       2_000

        next_pcm = :binary.copy(<<index, 0>>, 512)

        send_audio(
          attachment,
          identity,
          epoch,
          sequence + index,
          (sequence + index) * 512,
          next_pcm
        )

        assert_receive {:scribe_audio, ^wire, ^next_pcm}, 2_000
      end

      if @enabled and @failure == :hang do
        {task, _monitor} = inference
        reference = make_ref()
        send(task, {:diagnostic_still_blocked, self(), reference})
        assert_receive {:diagnostic_still_blocked, ^task, ^reference}, 1_000
      end

      change_diagnostics(false, c.settings_revision)
      await_diagnostic_drain(identity)

      if inference do
        {task, monitor} = inference
        assert_receive {:DOWN, ^monitor, :process, ^task, _reason}, 2_000
      else
        refute_received {:diagnostic_failure_started, _, _}
      end

      for marker <- [9, 1, 2] do
        delivered = :binary.copy(<<marker, 0>>, 512)
        refute_received {:scribe_audio, ^wire, ^delivered}
      end

      refute_received {:scribe_commit, ^wire}
      refute_received {:vxpipe_connection_unavailable, _}
      GenServer.stop(attachment.room_authority, :shutdown)

      assert_complete_text_trace(
        connection,
        identity,
        Enum.map(1..2, &"Continue the call #{&1}.")
      )
    end
  end

  for failure <- [:error, :blocked], vad <- [false, true], enabled <- [false, true] do
    @tag matrix: true, storage_failure: failure, vad: vad, diagnostics_enabled: enabled
    test "diagnostic storage #{failure} preserves calls with Silero #{vad} and collection #{enabled}",
         c do
      {call, connection, attachment, wire, identity} = call(c.options, c.vad, :llm, true)
      pace(32)
      epoch = make_ref()

      sequence =
        if c.diagnostics_enabled,
          do: discover_with_audio(attachment, identity, epoch, wire),
          else: 0

      failure = c.storage_failure

      write =
        if c.diagnostics_enabled do
          assert_receive {:diagnostic_storage_attempt, ^failure, task}, 2_000
          {task, Process.monitor(task)}
        end

      for index <- 1..2 do
        pcm = :binary.copy(<<50 + index, 0>>, 512)
        send_audio(attachment, identity, epoch, sequence + index, (sequence + index) * 512, pcm)
        assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
        if c.vad, do: assert_receive({:matrix_inference, :operational, _, ^pcm}, 2_000)

        text = "Continue during diagnostic storage failure #{index}."
        emit_scribe_turn(wire, text)
        assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000
        assert input.text == text
        assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
        assert output.text == "Acknowledged."
        assert output.correlation_id == input.correlation_id
        turn_id = input.correlation_id

        assert_receive {:vxpipe_event,
                        %CallEngine.Event.AgentTurnCompleted{correlation_id: ^turn_id}},
                       2_000
      end

      # Prove both turns completed while the same repository attempt was held.
      if c.diagnostics_enabled and failure == :blocked do
        {task, _monitor} = write
        reference = make_ref()
        send(task, {:still_blocked, self(), reference})
        assert_receive {:storage_still_blocked, ^task, ^reference}, 500
      end

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity, 5_000)
      await(fn -> Task.Supervisor.children(__MODULE__.Writes) == [] end)

      if write do
        {task, monitor} = write
        assert_receive {:DOWN, ^monitor, :process, ^task, _}, 1_000
      else
        refute_received {:diagnostic_storage_attempt, _, _}
      end

      assert {:ok, %{entries: []}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      for marker <- 51..52 do
        pcm = :binary.copy(<<marker, 0>>, 512)
        refute_received {:scribe_audio, _, ^pcm}
        refute_received {:matrix_inference, :operational, _, ^pcm}
      end

      refute_received {:scribe_commit, _}
      refute_received {:vxpipe_connection_unavailable, _}

      assert_complete_text_trace(
        connection,
        identity,
        Enum.map(1..2, &"Continue during diagnostic storage failure #{&1}.")
      )
    end
  end

  for vad <- [false, true], enabled <- [false, true] do
    @tag matrix: true, missing_diagnostic_model: true, vad: vad, diagnostics_enabled: enabled
    test "missing benchmark model preserves call behavior with Silero #{vad} and collection #{enabled}",
         c do
      {call, connection, attachment, wire, identity} = call(c.options, c.vad, :llm, true)
      pace(32)
      epoch = make_ref()

      sequence =
        if c.diagnostics_enabled,
          do: discover_with_audio(attachment, identity, epoch, wire),
          else: 0

      pcm = :binary.copy(<<41, 0>>, 512)
      send_audio(attachment, identity, epoch, sequence, sequence * 512, pcm)
      assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
      if c.vad, do: assert_receive({:matrix_inference, :operational, _, ^pcm}, 2_000)
      if c.diagnostics_enabled and not c.vad, do: assert_receive(:diagnostic_model_missing, 2_000)

      for index <- 1..2 do
        text = "Continue without the benchmark model #{index}."
        emit_scribe_turn(wire, text)
        assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000
        assert input.text == text
        assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
        assert output.text == "Acknowledged."
        assert output.correlation_id == input.correlation_id
        turn_id = input.correlation_id

        assert_receive {:vxpipe_event,
                        %CallEngine.Event.AgentTurnCompleted{correlation_id: ^turn_id}},
                       2_000

        marker = :binary.copy(<<41 + index, 0>>, 512)

        send_audio(
          attachment,
          identity,
          epoch,
          sequence + index,
          (sequence + index) * 512,
          marker
        )

        assert_receive {:scribe_audio, ^wire, ^marker}, 2_000
        if c.vad, do: assert_receive({:matrix_inference, :operational, _, ^marker}, 2_000)
      end

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)

      assert {:ok, %{entries: runs}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      cond do
        not c.diagnostics_enabled -> assert runs == []
        not c.vad -> assert Enum.any?(runs, &(:observer_unavailable in &1.run.reasons))
        true -> assert runs != []
      end

      if c.vad or not c.diagnostics_enabled, do: refute_received(:diagnostic_model_missing)

      for marker <- 41..43 do
        pcm = :binary.copy(<<marker, 0>>, 512)
        refute_received {:scribe_audio, _, ^pcm}
        refute_received {:matrix_inference, _, _, ^pcm}
      end

      refute_received {:scribe_commit, _}
      refute_received {:vxpipe_connection_unavailable, _}

      assert_complete_text_trace(
        connection,
        identity,
        Enum.map(1..2, &"Continue without the benchmark model #{&1}.")
      )
    end
  end

  for vad <- [false, true] do
    @tag matrix: true, input_only: true, vad: vad
    test "two human STT inputs persist isolated rows without an agent, local Silero #{vad}", c do
      assert :ok = ModelFixture.arm(c.model, :failure)
      {call, connection, attachment, wire, identity} = call(c.options, c.vad, :humans)

      assert_receive {:diagnostic_peer, peer_connection, peer_attachment, peer_wire,
                      peer_identity}

      assert Enum.all?(Map.values(call.plan.participants), &(&1.kind == :human))
      assert :sys.get_state(attachment.room_authority).text_capability == nil
      epoch = make_ref()

      for {input_attachment, input_wire, input_identity, marker} <- [
            {attachment, wire, identity, 7},
            {peer_attachment, peer_wire, peer_identity, 9}
          ] do
        sequence = discover_with_audio(input_attachment, input_identity, epoch, input_wire)
        pcm = :binary.copy(<<marker, 0>>, 512)
        send_audio(input_attachment, input_identity, epoch, sequence, sequence * 512, pcm)
        assert_receive {:scribe_audio, ^input_wire, ^pcm}, 2_000
        inference = if c.vad, do: :operational, else: :benchmark
        assert_receive {:matrix_inference, ^inference, _, ^pcm}, 2_000
        refute_received {:matrix_inference, _, _, ^pcm}
        emit_scribe_turn(input_wire, "Human conversation #{marker}.")
        participant = input_identity.participant_id

        assert_receive {:vxpipe_event,
                        %ParticipantTranscription{final: true, participant_id: ^participant} =
                          input},
                       2_000

        run =
          await(fn ->
            case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
              {:ok, %{entries: entries}} ->
                Enum.find_value(entries, fn %{run: run} ->
                  if run.participant_id == participant, do: run
                end)

              _ ->
                nil
            end
          end)

        row =
          await(fn ->
            case LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil) do
              {:ok, [row]} -> row
              _ -> nil
            end
          end)

        assert run.connection_id == input_identity.connection_id

        assert run.profile.inference_source ==
                 if(c.vad, do: :operational_reuse, else: :benchmark_only)

        assert row.turn_id == input.correlation_id
        assert row.landmarks_us[:provider_end_received] != nil
        assert row.landmarks_us[:room_turn_completed] != nil
        assert row.landmarks_us[:first_response_text] == nil
        assert row.landmarks_us[:first_audio_started] == nil
      end

      assert %{active_sources: 2} = RoomService.status(RoomService.address(identity))

      assert {:ok, %{entries: entries}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      assert length(entries) == 2
      assert length(Enum.uniq_by(entries, & &1.run.participant_id)) == 2
      assert length(Enum.uniq_by(entries, & &1.run.id)) == 2
      refute_received {:scribe_commit, _}
      assert SpeechConnection.attachment(connection).media_ingress == attachment.media_ingress

      assert SpeechConnection.attachment(peer_connection).media_ingress ==
               peer_attachment.media_ingress

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)
      assert %{next_scenario: :failure, default_scenario: :success} = ModelFixture.status(c.model)

      for marker <- [7, 9] do
        pcm = :binary.copy(<<marker, 0>>, 512)
        refute_received {:matrix_inference, _, _, ^pcm}
        refute_received {:scribe_audio, _, ^pcm}
      end

      refute_received {:scribe_commit, _}
    end
  end

  for mode <- ["external", "hybrid"], vad <- [false, true] do
    @tag matrix: true, mixed_sts: true, mode: mode, vad: vad
    test "accepted human STT persists with #{mode} STS control, local Silero #{vad}", c do
      assert :ok = ModelFixture.arm(c.model, :failure)
      {call, _connection, attachment, wire, identity} = call(c.options, c.vad, {:sts, c.mode})
      state = :sys.get_state(attachment.room_authority)
      assert state.text_capability == nil
      assert state.speech_to_speech_capability != nil
      assert CallEngine.RoomAuthority.SpeechToSpeech.ActivityControl.mode(state) == c.mode
      stt = state.connections[identity.connection_id].speech_to_text.capability

      assert {:ok, %{activity_origin: origin}} =
               CallEngine.Capability.SpeechToText.input_binding(stt)

      assert origin.agent_id == state.speech_to_speech_capability.participant_id
      # Admission fences receipts at the startup millisecond; the first real
      # 32 ms audio frame arrives after that cutoff.
      pace(32)
      epoch = make_ref()
      sequence = discover_with_audio(attachment, identity, epoch, wire)
      pcm = :binary.copy(<<7, 0>>, 512)
      send_audio(attachment, identity, epoch, sequence, sequence * 512, pcm)
      assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
      inference = if c.vad, do: :operational, else: :benchmark
      assert_receive {:matrix_inference, ^inference, _, ^pcm}, 2_000

      :ok =
        Wire.deliver_frame(
          wire,
          JSON.encode!(%{
            "message_type" => "partial_transcript",
            "text" => "Accepted human input."
          })
        )

      activity =
        await(fn ->
          :sys.get_state(attachment.room_authority).speech_to_speech_capability.activity_turn
        end)

      assert activity.source == identity.connection_id
      assert activity.generation == origin.allocation_generation
      emit_scribe_turn(wire, "Accepted human input.")
      assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000

      run =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: [%{run: run}]}} -> run
            _ -> nil
          end
        end)

      row =
        await(fn ->
          case LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil) do
            {:ok, [row]} -> row
            _ -> nil
          end
        end)

      assert :sys.get_state(attachment.room_authority).speech_to_speech_capability.activity_turn ==
               nil

      assert run.profile.inference_source ==
               if(c.vad, do: :operational_reuse, else: :benchmark_only)

      assert run.participant_id == identity.participant_id
      assert run.connection_id == identity.connection_id
      assert row.turn_id == input.correlation_id
      assert row.landmarks_us[:provider_end_received] != nil
      assert row.landmarks_us[:room_turn_completed] != nil
      assert row.landmarks_us[:first_response_text] == nil
      assert row.landmarks_us[:first_audio_started] == nil
      assert %{active_sources: 1} = RoomService.status(RoomService.address(identity))
      assert %{next_scenario: :failure} = ModelFixture.status(c.model)
      refute_received {:scribe_commit, _}

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)
      refute_received {:matrix_inference, _, _, ^pcm}
      refute_received {:scribe_audio, _, ^pcm}
      refute_received {:scribe_commit, _}
    end
  end

  @tag matrix: true, mixed_sts: true
  test "native STS without human STT starts no diagnostic observer", c do
    {call, _connection, attachment, nil, identity} = call(c.options, false, :native_sts)
    state = :sys.get_state(attachment.room_authority)
    assert state.speech_to_speech_capability != nil
    assert state.connections[identity.connection_id].speech_to_text == nil
    assert attachment.media_ingress == nil
    session = :sys.get_state(state.speech_to_speech_capability.pid).session
    provider = CallEngine.Speech.Session.provider(session)
    assert Vxpipe.Providers.MorseCode.STSSession.input_quiescent?(provider)

    frame =
      struct!(
        AudioFrame,
        Map.merge(
          Map.take(identity, [
            :tenant_id,
            :room_id,
            :incarnation_id,
            :participant_id,
            :connection_id
          ]),
          %{
            source_epoch: nil,
            track_id: "configured-speech",
            codec: :linear16,
            sample_rate: 16_000,
            channels: 1,
            sequence_number: 0,
            timestamp: 0,
            payload: <<0::8192>>,
            received_at: System.monotonic_time(:millisecond)
          }
        )
      )

    assert :ok =
             CallEngine.TestTransferConnection.run(identity, fn ->
               CallEngine.push_speech_to_speech_audio(attachment, frame)
             end)

    assert {:ok, %{ingress: ingress}} =
             CallEngine.speech_to_speech_input_configuration(attachment)

    await(fn ->
      stats = CallEngine.Media.STSIngress.stats(ingress)
      stats.queued == 0 and not stats.in_flight?
    end)

    refute Vxpipe.Providers.MorseCode.STSSession.input_quiescent?(provider)

    assert %{active_sources: 0, pending?: false, last_reason: :no_candidates} =
             RoomService.scan(RoomService.address(identity))

    assert DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers)) == []
    assert {:ok, %{entries: []}} = LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)
    refute_received {:matrix_inference, _, _, _}
    refute_received {:scribe_started, _}
    GenServer.stop(attachment.room_authority, :shutdown)
    await_diagnostic_drain(identity)
  end

  for mode <- ["external", "hybrid"], vad <- [false, true] do
    @tag matrix: true, mixed_sts: true, stt_replacement: true, mode: mode, vad: vad
    test "#{mode} audio-policy routing replaces STT and creates a new diagnostic run, Silero #{vad}",
         c do
      {call, _connection, attachment, wire, identity} =
        call(c.options, c.vad, {:sts_routing, c.mode})

      pace(32)
      epoch = make_ref()
      _ = discover_with_audio(attachment, identity, epoch, wire)
      await(fn -> RoomService.status(RoomService.address(identity)).active_sources == 1 end)

      [{_, worker, _, _}] =
        DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers))

      input_handoff = CallEngine.Diagnostics.SourceWorker.handoff(worker)
      worker_down = Process.monitor(worker)
      original = :sys.get_state(attachment.room_authority)
      stt = original.connections[identity.connection_id].speech_to_text.capability

      assert {:ok, %{allocation_generation: old_generation}} =
               CallEngine.Capability.SpeechToText.input_binding(stt)

      old_run =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: [%{run: run}]}} -> run
            _ -> nil
          end
        end)

      emit_scribe_turn(wire, "Input before routing.")
      assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = before_input}, 2_000

      await(fn ->
        case LatencyStore.list_turns(Repo, call.tenant_key, call.id, old_run.id, 50, nil) do
          {:ok, [row]} -> row.turn_id == before_input.correlation_id
          _ -> false
        end
      end)

      privacy = Map.fetch!(call.plan.participants, "privacy")

      assert {:ok, _} =
               CallEngine.MediaPolicy.Authority.admit(
                 original.media_policy_authority,
                 privacy.participant_id
               )

      assert_receive {:scribe_started, restricted_wire}, 5_000

      :ok =
        Wire.deliver_frame(
          restricted_wire,
          JSON.encode!(%{
            "message_type" => "session_started",
            "session_id" => "restricted-scribe",
            "config" => echoed_settings()
          })
        )

      assert_receive {:DOWN, ^worker_down, :process, ^worker, _}, 2_000
      refute CallEngine.Diagnostics.CaptureHandoff.current?(input_handoff)

      assert {:ok, _} =
               CallEngine.MediaPolicy.Authority.leave(
                 original.media_policy_authority,
                 privacy.participant_id
               )

      assert_receive {:scribe_started, new_wire}, 5_000
      refute new_wire in [wire, restricted_wire]

      :ok =
        Wire.deliver_frame(
          new_wire,
          JSON.encode!(%{
            "message_type" => "session_started",
            "session_id" => "routed-scribe",
            "config" => echoed_settings()
          })
        )

      fresh =
        await(fn ->
          state = :sys.get_state(attachment.room_authority)
          if state.speech_to_speech_capability != nil, do: state
        end)

      new_stt = fresh.connections[identity.connection_id].speech_to_text.capability

      assert {:ok, %{allocation_generation: new_generation}} =
               CallEngine.Capability.SpeechToText.input_binding(new_stt)

      refute new_generation == old_generation

      closed_run =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: entries}} ->
              Enum.find_value(entries, fn %{run: run} ->
                if run.id == old_run.id and run.closed_at != nil, do: run
              end)

            _ ->
              nil
          end
        end)

      assert :source_changed in closed_run.reasons

      assert {:error, :unavailable} =
               CallEngine.Diagnostics.CaptureHandoff.offer(
                 input_handoff,
                 {:room_turn_completed, old_generation, make_ref(), "stale-turn", "stale-command",
                  System.monotonic_time(:microsecond)}
               )

      fresh_attachment = CallEngine.TestTransferConnection.attachment(identity)
      pace(32)
      _ = discover_with_audio(fresh_attachment, identity, make_ref(), new_wire)

      :ok =
        Wire.deliver_frame(
          new_wire,
          JSON.encode!(%{
            "message_type" => "partial_transcript",
            "text" => "Input after routing."
          })
        )

      active_turn =
        await(fn ->
          state = :sys.get_state(attachment.room_authority)
          state.connections[identity.connection_id].speech_to_text.turn
        end)

      assert active_turn.allocation_generation == new_generation

      assert {:ok, %{audio_origin: origin}} =
               CallEngine.Capability.SpeechToText.input_binding(new_stt)

      stale = %CallEngine.Provider.SpeechToText.Signal{
        kind: :turn_ended,
        provider_sequence: 999,
        allocation_generation: old_generation,
        turn_ref: active_turn.turn_ref,
        provider_turn_index: active_turn.provider_turn_index,
        policy_revision: active_turn.policy_revision,
        audio_input_interval: origin.audio_input_interval,
        audio_output_interval: origin.audio_output_interval,
        text: "Stale routing input."
      }

      send(
        attachment.room_authority,
        {:vxpipe_stt_signal, new_stt,
         Map.take(identity, [
           :tenant_id,
           :room_id,
           :incarnation_id,
           :participant_id,
           :connection_id
         ]), stale, nil}
      )

      after_stale = :sys.get_state(attachment.room_authority)
      assert after_stale.connections[identity.connection_id].speech_to_text.turn == active_turn
      refute_received {:vxpipe_event, %ParticipantTranscription{text: "Stale routing input."}}

      emit_scribe_turn(new_wire, "Input after routing.")
      assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = after_input}, 2_000

      new_run =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: entries}} ->
              Enum.find_value(entries, fn %{run: run} -> if run.id != old_run.id, do: run end)

            _ ->
              nil
          end
        end)

      assert new_run.participant_id == old_run.participant_id
      assert new_run.connection_id == old_run.connection_id
      refute new_run.id == old_run.id

      new_row =
        await(fn ->
          case LatencyStore.list_turns(Repo, call.tenant_key, call.id, new_run.id, 50, nil) do
            {:ok, [row]} -> if row.turn_id == after_input.correlation_id, do: row
            _ -> nil
          end
        end)

      assert {:ok, [old_row]} =
               LatencyStore.list_turns(Repo, call.tenant_key, call.id, old_run.id, 50, nil)

      assert old_row.turn_id == before_input.correlation_id
      refute old_row.turn_id == after_input.correlation_id
      refute new_row.stt_allocation_id == old_row.stt_allocation_id

      assert {:ok, %{entries: entries}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      assert length(entries) == 2
      assert %{active_sources: 1} = RoomService.status(RoomService.address(identity))

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)
      refute_received {:scribe_commit, _}
    end
  end

  for vad <- [false, true] do
    @tag matrix: true, routing: true, transfer_continuity: true, vad: vad
    test "configured agent transfer preserves continuous input and acknowledged audio, Silero #{vad}",
         c do
      {call, connection, attachment, wire, identity} = call(c.options, c.vad, :transfer)
      assert_receive {:test_tts_transport_started, source_voice, _}, 5_000
      epoch = make_ref()
      sequence = discover_with_audio(attachment, identity, epoch, wire)
      await(fn -> RoomService.status(RoomService.address(identity)).active_sources == 1 end)
      original_service = GenServer.whereis(RoomService.address(identity))

      [{_, original_worker, _, _}] =
        DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers))

      original_input = Vxpipe.CallEngine.Diagnostics.SourceWorker.handoff(original_worker)

      original_run =
        await(fn ->
          case LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil) do
            {:ok, %{entries: [%{run: run}]}} -> run
            _ -> nil
          end
        end)

      emit_scribe_turn(wire, "Please transfer me.")
      assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = first_input}, 2_000
      assert_receive {:test_agent_runtime_stream, source_model, _}, 2_000

      mode = if c.vad, do: :operational, else: :benchmark
      before_pcm = :binary.copy(<<19, 0>>, 512)
      pace(32)
      send_audio(attachment, identity, epoch, sequence, sequence * 512, before_pcm)
      assert_receive {:scribe_audio, ^wire, ^before_pcm}, 2_000
      assert_receive {:matrix_inference, ^mode, before_samples, ^before_pcm}, 2_000

      before_transfer =
        await(fn ->
          state = :sys.get_state(original_worker)

          if state.timeline.clock.last_input != nil and
               state.timeline.clock.last_input.sample_timestamp == sequence * 512 and
               state.boundary.samples == before_samples + 512,
             do: state
        end)

      sequence = sequence + 1

      {:ok, transfer} =
        Vxpipe.AgentRuntime.ToolCall.new(
          id: "timing-transfer",
          name: "transfer",
          arguments: %{"destination" => "specialist"}
        )

      {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "", tool_calls: [transfer])
      send(source_model, {:test_agent_runtime_response, {:ok, response}})

      assert_receive {:test_tts_transport_start_blocked, preparing_voice, _}, 5_000
      preparing = :sys.get_state(attachment.room_authority)
      assert preparing.pending_participant_transfer != nil
      assert MapSet.member?(preparing.held_participant_ids, identity.participant_id)
      before_audio = :sys.get_state(original_worker)
      assert before_audio.epoch == before_transfer.epoch
      assert before_audio.boundary.samples == before_transfer.boundary.samples
      assert before_audio.timeline == before_transfer.timeline

      during_samples =
        for index <- 0..2 do
          pace(32)
          pcm = :binary.copy(<<20 + index, 0>>, 512)
          send_audio(attachment, identity, epoch, sequence + index, (sequence + index) * 512, pcm)
          assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
          assert_receive {:matrix_inference, ^mode, samples, ^pcm}, 2_000

          observed =
            await(fn ->
              state = :sys.get_state(original_worker)

              if state.timeline.clock.last_input != nil and
                   state.timeline.clock.last_input.sample_timestamp == (sequence + index) * 512 and
                   state.boundary.samples == samples + 512,
                 do: state
            end)

          assert observed.epoch == before_audio.epoch
          assert observed.timeline.source_epoch == before_audio.timeline.source_epoch
          assert CallEngine.Diagnostics.CaptureHandoff.current?(original_input)
          assert :sys.get_state(attachment.room_authority).pending_participant_transfer != nil
          samples
        end

      [first_sample, second_sample, third_sample] = during_samples
      assert first_sample == before_samples + 512
      assert second_sample == first_sample + 512
      assert third_sample == second_sample + 512
      assert RoomService.status(RoomService.address(identity)).active_sources == 1

      assert [{_, ^original_worker, _, _}] =
               DynamicSupervisor.which_children(RoomSupervisor.address(identity, :workers))

      send(preparing_voice, :release_test_tts_transport_start)

      assert_receive {:vxpipe_event,
                      %CallEngine.Event.ToolCallCompleted{tool_call_id: "timing-transfer"}},
                     5_000

      assert_receive {:test_tts_transport_started, destination_voice, _}, 5_000
      refute source_voice == destination_voice
      # Routing changes the agent, while the caller retains its STT session.
      assert SpeechConnection.attachment(connection).media_ingress == attachment.media_ingress
      refute_received {:scribe_started, _}
      # Agent routing preserves the accepted input and its existing acoustic run.
      assert GenServer.whereis(RoomService.address(identity)) == original_service
      _ = RoomService.scan(RoomService.address(identity))

      assert {:ok, %{entries: [%{run: after_transfer}]}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      assert after_transfer.id == original_run.id
      assert after_transfer.closed_at == nil

      assert Vxpipe.CallEngine.Diagnostics.CaptureHandoff.current?(original_input)

      pcm = :binary.copy(<<7, 0>>, 512)
      send_audio(attachment, identity, epoch, sequence + 3, (sequence + 3) * 512, pcm)
      assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
      assert_receive {:matrix_inference, ^mode, samples, ^pcm}, 2_000
      assert samples == third_sample + 512

      await(fn ->
        state = :sys.get_state(original_worker)
        assert state.epoch == before_audio.epoch

        state.timeline.clock.last_input != nil and
          state.timeline.clock.last_input.sample_timestamp == (sequence + 3) * 512 and
          state.boundary.samples == samples + 512
      end)

      refute_received {:scribe_observing, ^wire, _}
      emit_scribe_turn(wire, "Please answer now.")
      assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = second_input}, 2_000
      refute second_input.correlation_id == first_input.correlation_id
      {destination_model, request} = specialist_request()
      assert hd(request.messages).content =~ "Handle specialist requests."

      text =
        JSON.encode!(%{
          type: "participant_message",
          participant_id: "agent",
          agent_mode: "speaker",
          message: "The specialist answers."
        })

      {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: text)
      send(destination_model, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
      assert output.correlation_id == second_input.correlation_id
      assert output.text == "The specialist answers."
      assert_receive {:test_tts_control, ^destination_voice, _}, 2_000

      CallEngine.TestTextToSpeechTransport.deliver_control(
        destination_voice,
        JSON.encode!(%{type: "SpeechStarted", speech_id: "diagnostic-spoken"})
      )

      CallEngine.TestTextToSpeechTransport.deliver_audio(destination_voice, <<1, 0, 2, 0>>)
      correlation = second_input.correlation_id
      assert_receive {:test_audio_output, sink, %{correlation_id: ^correlation} = audio}, 2_000
      assert audio.command_id == output.command_id

      text_only =
        await(fn ->
          case diagnostic_turn(call, second_input.correlation_id) do
            %{landmarks_us: %{first_response_text: text}} = row when is_integer(text) -> row
            _ -> nil
          end
        end)

      assert is_integer(text_only.landmarks_us.first_response_text)
      refute Map.has_key?(text_only.landmarks_us, :first_audio_started)
      :ok = CallEngine.TestAudioOutputSink.playback_started(sink)
      assert_receive {:vxpipe_event, %CallEngine.Event.AgentSpeechStarted{} = started}, 2_000
      assert started.correlation_id == second_input.correlation_id
      assert started.command_id == output.command_id

      row =
        await(fn ->
          case diagnostic_turn(call, second_input.correlation_id) do
            %{landmarks_us: %{first_audio_started: started}} = row when is_integer(started) -> row
            _ -> nil
          end
        end)

      assert row.run_id == original_run.id
      assert row.response_turn_id == output.command_id
      assert is_integer(row.landmarks_us.first_response_text)
      assert row.landmarks_us.first_audio_started >= row.landmarks_us.first_response_text

      CallEngine.TestTextToSpeechTransport.deliver_control(
        destination_voice,
        JSON.encode!(%{type: "SpeechMetadata", speech_id: "diagnostic-spoken"})
      )

      assert_receive {:test_audio_output_finish, ^sink, ^correlation}, 2_000
      :ok = CallEngine.TestAudioOutputSink.playback_completed(sink)

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 identity.tenant_id,
                 identity.room_id,
                 identity.incarnation_id
               )

      GenServer.stop(attachment.room_authority, :shutdown)
      assert_receive {:DOWN, ^completion, :process, _, _}, 2_000
      await_diagnostic_drain(identity)

      for marker <- [7, 19, 20, 21, 22] do
        pcm = :binary.copy(<<marker, 0>>, 512)
        refute_received {:scribe_audio, _, ^pcm}
        refute_received {:matrix_inference, _, _, ^pcm}
      end

      refute_received {:scribe_commit, _}
      tool_only = diagnostic_turn(call, first_input.correlation_id)
      assert tool_only.run_id == original_run.id
      assert tool_only.response_turn_id == nil
      refute Map.has_key?(tool_only.landmarks_us, :first_response_text)
      refute Map.has_key?(tool_only.landmarks_us, :first_audio_started)
    end
  end

  defp assert_complete_text_trace(connection, identity, texts, scope \\ :all) do
    # RoomAuthority publishes these events directly. Its DOWN reaches the same
    # connection after its preceding events; the forwarded close is our barrier.
    assert_receive {:configured_speech_closed, ^connection}, 2_000
    assert_receive {:control_trace_agent, ^connection, agent}
    events = collect_control_events(scope)

    assert length(events) == length(texts) * 6,
           "unexpected event sequence: #{inspect(Enum.map(events, & &1.__struct__))}"

    assert Enum.all?(events, &(is_binary(&1.id) and byte_size(&1.id) > 0))
    assert length(Enum.uniq_by(events, & &1.id)) == length(events)
    sequences = Enum.map(events, & &1.sequence)
    assert Enum.all?(sequences, &(is_integer(&1) and &1 > 0))
    assert sequences == Enum.sort(Enum.uniq(sequences))
    turns = Enum.chunk_every(events, 6)

    assert length(Enum.uniq_by(turns, fn [start | _] -> start.correlation_id end)) ==
             length(texts)

    assert length(Enum.uniq_by(turns, fn [start | _] -> start.command_id end)) == length(texts)

    for {{[start | _] = turn, text}, index} <- Enum.with_index(Enum.zip(turns, texts)) do
      assert is_binary(start.command_id) and byte_size(start.command_id) > 0
      assert is_binary(start.correlation_id) and byte_size(start.correlation_id) > 0

      common = %{
        tenant_id: identity.tenant_id,
        room_id: identity.room_id,
        incarnation_id: identity.incarnation_id,
        connection_id: identity.connection_id,
        command_id: start.command_id,
        correlation_id: start.correlation_id,
        schema_version: 1
      }

      human = identity.participant_id

      expected = [
        {CallEngine.Event.ParticipantTurnStarted, %{participant_id: human, modality: :audio}},
        {ParticipantTranscription,
         %{participant_id: human, text: text, final: false, provider_turn_index: index}},
        {ParticipantTranscription,
         %{participant_id: human, text: text, final: true, provider_turn_index: index}},
        {CallEngine.Event.ParticipantTurnCompleted,
         %{participant_id: human, modality: :audio, endpointing: nil}},
        {CallEngine.Event.TextOutput,
         %{
           participant_id: agent,
           source_participant_id: human,
           text: "Acknowledged.",
           aggregated_by: :sentence,
           will_be_spoken: false,
           agent_mode: :speaker
         }},
        {CallEngine.Event.AgentTurnCompleted,
         %{participant_id: agent, source_participant_id: human, outcome: :completed}}
      ]

      for {event, {module, fields}} <- Enum.zip(turn, expected) do
        assert event.__struct__ == module
        assert %DateTime{} = event.occurred_at

        assert event |> Map.from_struct() |> Map.drop([:id, :sequence, :occurred_at]) ==
                 Map.merge(common, fields)
      end
    end

    events
  end

  defp assert_peer_projection(connection, source_connection_id, events) do
    for expected <- events do
      assert_receive {:configured_public_event, ^connection,
                      %{connection_id: ^source_connection_id} = observed},
                     2_000

      assert observed == expected
    end
  end

  defp assert_stored_input_turns(turns, events, expected_count \\ 2) do
    assert length(turns) == expected_count

    canonical =
      for %CallEngine.Event.ParticipantTurnCompleted{} = event <- events,
          do: event.correlation_id

    assert MapSet.new(turns, & &1.turn_id) == MapSet.new(canonical)
  end

  defp collect_control_events(:all) do
    receive do
      {:configured_public_event, event} -> [event | collect_control_events(:all)]
    after
      0 -> []
    end
  end

  defp collect_control_events({:source, connection, connection_id} = scope) do
    receive do
      {:configured_public_event, ^connection, %{connection_id: ^connection_id} = event} ->
        [event | collect_control_events(scope)]
    after
      0 -> []
    end
  end

  defp collect_control_events(room_id) do
    receive do
      {:configured_public_event, %{room_id: ^room_id} = event} ->
        [event | collect_control_events(room_id)]
    after
      0 -> []
    end
  end

  defp writer_failure_turn(c, attachment, wire, identity, epoch, sequence, marker) do
    pcm = :binary.copy(<<marker, 0>>, 512)
    pace(32)
    send_audio(attachment, identity, epoch, sequence, sequence * 512, pcm)
    assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000
    if c.vad, do: assert_receive({:matrix_inference, :operational, _, ^pcm}, 2_000)

    if c.diagnostics_enabled and not c.vad and marker != 72,
      do: assert_receive({:matrix_inference, :benchmark, _, ^pcm}, 2_000)

    text = "Writer failure turn #{marker}."
    emit_scribe_turn(wire, text)
    assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000
    assert input.text == text
    assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
    assert output.text == "Acknowledged."
    assert output.correlation_id == input.correlation_id
    turn_id = input.correlation_id

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnCompleted{correlation_id: ^turn_id}},
                   2_000

    %{turn_id: input.correlation_id, pcm: pcm}
  end

  defp resume_diagnostic_worker(worker) do
    :sys.resume(worker)
  catch
    :exit, _ -> :ok
  end

  defp assert_saturated_worker_bounds(worker, handoff) do
    stats = CaptureHandoff.stats(handoff)
    assert stats.pending_count <= handoff.maximum_count
    assert stats.pending_bytes <= handoff.maximum_bytes
    assert {:message_queue_len, count} = Process.info(worker, :message_queue_len)
    # Captured packets plus bounded timer/lifecycle messages, while sys-suspended.
    assert count <= handoff.maximum_count + 8
    Map.put(stats, :mailbox_count, count)
  end

  defp lifecycle_turn(c, call, attachment, wire, identity, epoch, sequence, cycle, phase) do
    phase_number = %{enabled: 0, disabled: 1, reenabled: 2} |> Map.fetch!(phase)
    pcm = :binary.copy(<<cycle * 3 + phase_number, 0>>, 512)
    pace(32)
    send_audio(attachment, identity, epoch, sequence, sequence * 512, pcm)
    assert_receive {:scribe_audio, ^wire, ^pcm}, 2_000

    if c.vad do
      assert_receive {:matrix_inference, :operational, _, ^pcm}, 2_000
    else
      if phase != :disabled, do: assert_receive({:matrix_inference, :benchmark, _, ^pcm}, 2_000)
    end

    text = "Lifecycle #{cycle} #{phase}."
    emit_scribe_turn(wire, text)
    assert_receive {:vxpipe_event, %ParticipantTranscription{final: true} = input}, 2_000
    assert input.text == text
    assert_receive {:vxpipe_event, %CallEngine.Event.TextOutput{} = output}, 2_000
    assert output.text == "Acknowledged."
    assert output.correlation_id == input.correlation_id
    turn_id = input.correlation_id

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnCompleted{correlation_id: ^turn_id}},
                   2_000

    refute_received {:scribe_audio, ^wire, ^pcm}
    refute_received {:matrix_inference, _, _, ^pcm}

    run =
      if phase == :disabled do
        assert diagnostic_turn(call, input.correlation_id) == nil
        nil
      else
        turn = await(fn -> diagnostic_turn(call, input.correlation_id) end)

        assert {:ok, %{entries: entries}} =
                 LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

        %{run: run} = Enum.find(entries, &(&1.run.id == turn.run_id))
        run
      end

    %{run: run, turn_id: input.correlation_id, pcm: pcm}
  end

  # Opt-in Linux process RSS includes native allocations; BEAM heap size does not.
  # Sample after room completion and diagnostic drain, without forcing collection.
  defp diagnostic_rss_kib do
    status = File.read!("/proc/#{System.pid()}/status")
    [_, rss] = Regex.run(~r/^VmRSS:\s+(\d+) kB$/m, status)
    String.to_integer(rss)
  end

  defp assert_diagnostic_slots_released do
    await(fn ->
      Vxpipe.CallEngine.Diagnostics.SourceAdmission.status(
        Vxpipe.CallEngine.Diagnostics.SourceAdmission
      ) ==
        %{active_sources: 0, occupied_slots: 0}
    end)

    await(fn -> Task.Supervisor.children(__MODULE__.Tasks) == [] end)
    await(fn -> Task.Supervisor.children(__MODULE__.Writes) == [] end)

    admission =
      Vxpipe.CallEngine.Speech.ActivityRuntime.diagnostic_admission(__MODULE__.Runtime)

    assert Vxpipe.CallEngine.Diagnostics.InferenceAdmission.pending(admission) == 0
  end

  defp diagnostic_turn(call, turn_id) do
    {:ok, %{entries: runs}} = LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

    Enum.find_value(runs, fn %{run: run} ->
      {:ok, turns} = LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)
      Enum.find(turns, &(&1.turn_id == turn_id))
    end)
  end

  defp emit_scribe_turn(wire, text) do
    for {kind, value} <- [
          {"partial_transcript", text},
          {"committed_transcript", text},
          {"partial_transcript", ""}
        ] do
      :ok = Wire.deliver_frame(wire, JSON.encode!(%{"message_type" => kind, "text" => value}))
    end
  end

  defp change_diagnostics(enabled, revision) do
    assert {:ok, %{enabled: ^enabled, revision: next}} =
             DiagnosticsSettingsStore.update(operator(), enabled, revision)

    expected = {if(enabled, do: :enabled, else: :disabled), next}

    await(fn ->
      Vxpipe.CallEngine.Diagnostics.SettingsProjection.status(__MODULE__.Projection) == expected
    end)
  end

  defp await_diagnostic_drain(identity, timeout \\ 2_000) do
    await(
      fn ->
        Enum.all?(
          [RoomSupervisor.address(identity, :workers), __MODULE__.Collectors, __MODULE__.Writers],
          fn supervisor ->
            try do
              case GenServer.whereis(supervisor) do
                nil -> true
                pid -> DynamicSupervisor.count_children(pid).active == 0
              end
            catch
              :exit, {reason, _} when reason in [:noproc, :shutdown] -> false
            end
          end
        )
      end,
      timeout
    )
  end

  defp benchmark_classifier(parent, nil), do: matrix_classifier(parent, :benchmark)

  defp benchmark_classifier(parent, failure) do
    normal = matrix_classifier(parent, :benchmark)

    fn model, stream, pcm ->
      if pcm == :binary.copy(<<9, 0>>, 512) do
        send(parent, {:diagnostic_failure_started, failure, self()})

        case failure do
          :crash -> exit(:synthetic_diagnostic_failure)
          :hang -> hold_diagnostic_inference(fn -> normal.(model, stream, pcm) end)
        end
      else
        normal.(model, stream, pcm)
      end
    end
  end

  defp hold_diagnostic_inference(release) do
    receive do
      {:diagnostic_still_blocked, observer, reference} ->
        send(observer, {:diagnostic_still_blocked, self(), reference})
        hold_diagnostic_inference(release)

      :release_diagnostic_inference ->
        release.()
    end
  end

  defp actual_inference_evidence do
    receive do
      {:actual_inference, mode, count, fingerprint, at} ->
        [{mode, count, fingerprint, at} | actual_inference_evidence()]
    after
      0 -> []
    end
  end

  defp actual_loader(parent, mode) do
    fn ->
      send(parent, {:actual_model_load_started, mode})
      Silero.load()
    end
  end

  defp actual_classifier(parent, mode) do
    fn model, stream, pcm ->
      result = Silero.push(stream, model, pcm)
      finished_at = System.monotonic_time(:microsecond)

      case result do
        {:ok, _, probabilities} ->
          send(
            parent,
            {:actual_inference, mode, length(probabilities), :crypto.hash(:sha256, pcm),
             finished_at}
          )

        _ ->
          send(parent, {:actual_inference_failed, mode})
      end

      result
    end
  end

  defp matrix_classifier(parent, mode) do
    fn _model, stream, pcm ->
      send(parent, {:matrix_inference, mode, stream.samples, pcm})
      count = div(byte_size(pcm), 1_024)
      {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.0, count)}
    end
  end

  defp call(options, vad \\ false, scenario \\ :llm, audit_events? \\ false) do
    routing? = scenario == :transfer
    input_only? = scenario == :humans
    concurrent? = match?({:concurrent_llm, _}, scenario)
    two_inputs? = scenario == {:concurrent_llm, 2}

    sts_mode =
      case scenario do
        {:sts, mode} -> mode
        {:sts_routing, mode} -> mode
        :native_sts -> "provider"
        _ -> nil
      end

    {:ok, tenant, key} = Administration.bootstrap_tenant("Diagnostic fixture", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    credential_name = "diagnostic-scribe-#{tenant.key}"

    assert {:ok, _} =
             ProviderCredentials.provision(
               :platform,
               "elevenlabs",
               credential_name,
               "api_key",
               %{"api_key" => "synthetic"},
               options
             )

    source = %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "echo"},
          speech_to_text: %{
            provider: "elevenlabs",
            model: "scribe_v2_realtime",
            credential_name: credential_name,
            vad: vad
          }
        }
      },
      media_policy: %{record_audio: true, save_transcripts: true},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"}
        }
      }
    }

    source =
      if two_inputs? do
        put_in(source, [:participants, "guest"], %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        })
      else
        source
      end

    source =
      if input_only? do
        source
        |> update_in([:defaults, :capabilities], &Map.delete(&1, :model_inference))
        |> put_in([:participants, "assistant"], %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        })
      else
        source
      end

    source =
      if routing? do
        assert {:ok, _} =
                 ProviderCredentials.provision(
                   :platform,
                   "deepgram",
                   "diagnostic-tts",
                   "api_key",
                   %{"api_key" => "synthetic"},
                   options
                 )

        source
        |> put_in([:defaults, :capabilities, :text_to_speech], %{
          provider: "deepgram",
          model: "flux-test-voice",
          credential_name: "diagnostic-tts",
          options: %{encoding: "linear16", sample_rate: 48_000}
        })
        |> put_in([:participants, "assistant", :transfers], ["specialist"])
        |> put_in([:participants, "specialist"], %{
          type: "agent",
          prompt: "Handle specialist requests.",
          first_message: %{mode: "wait_for_input"}
        })
      else
        source
      end

    source =
      if sts_mode do
        source =
          source
          |> Map.put(:wait_sounds, %{call_setup: nil})
          |> update_in([:defaults, :capabilities], &Map.delete(&1, :model_inference))
          |> put_in([:participants, "assistant", :capabilities], %{
            speech_to_speech: %{
              provider: "morse",
              model: "morse",
              options: %{turn_control: sts_mode, unit_duration_ms: 20}
            }
          })

        if scenario == :native_sts,
          do: update_in(source, [:defaults, :capabilities], &Map.delete(&1, :speech_to_text)),
          else: source
      else
        source
      end

    source =
      if match?({:sts_routing, _}, scenario) do
        put_in(source, [:participants, "privacy"], %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{},
          while_present: %{audio_routes: %{}}
        })
      else
        source
      end

    assert {:ok, draft} = Calls.save_call_spec(tenant.key, source, options)
    assert draft.validation_errors == []

    assert {:ok, publication} =
             Calls.publish_call_spec(tenant.key, draft.call_spec_id, draft.revision, options)

    assert {:ok, prepared} =
             Calls.claim_call(actor, tenant.key, publication.call_spec_id, %{}, nil, nil, options)

    assert {:ok, token} =
             Calls.issue_call_join_token(actor, tenant.key, prepared.id, nil, options)

    assert {:ok, claim} =
             Calls.claim_join_token(
               token.secret,
               %{
                 tenant_key: tenant.key,
                 call_id: prepared.id,
                 participant_key: token.participant_key
               },
               options
             )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call_raw(claim.call.plan,
               credential_source: {ProviderCredentialSource, options}
             )

    assert {:ok, :admit, _} = Calls.bind_call_admission(claim, room.incarnation_id, options)
    participant = Map.fetch!(claim.call.plan.participants, claim.call.plan.entry_caller)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: tenant.key,
               actor_id: claim.call.plan.actor_id,
               room_id: prepared.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "diagnostic-caller",
               deadline: DateTime.add(DateTime.utc_now(), 20, :second)
             )

    sink =
      if routing? or sts_mode != nil,
        do: start_supervised!({CallEngine.TestAudioOutputSink, observer: self()})

    connection =
      if sts_mode do
        start_supervised!(
          {CallEngine.TestTransferConnection,
           command: command,
           observer: self(),
           output: sink,
           input_track: %{
             track_id: "configured-speech",
             codec: :linear16,
             sample_rate: 16_000,
             channels: 1
           }}
        )
      else
        start_supervised!(
          Supervisor.child_spec(
            {SpeechConnection,
             command: command, observer: self(), output: sink, audit_events?: audit_events?},
            id:
              if(concurrent?,
                do: {:speech_connection, command.room_id, command.connection_id},
                else: SpeechConnection
              )
          )
        )
      end

    if audit_events? do
      agent = Map.fetch!(claim.call.plan.participants, claim.call.plan.entry_receiver)
      send(self(), {:control_trace_agent, connection, agent.participant_id})
    end

    assert {:ok, attachment} = SpeechConnection.attach(connection)

    on_exit(fn ->
      try do
        GenServer.stop(attachment.room_authority, :shutdown)
      catch
        :exit, _ -> :ok
      end
    end)

    wire =
      if scenario == :native_sts do
        nil
      else
        assert_receive {:scribe_started, wire}, 5_000

        :ok =
          Wire.deliver_frame(
            wire,
            JSON.encode!(%{
              "message_type" => "session_started",
              "session_id" => "synthetic",
              "config" => echoed_settings()
            })
          )

        wire
      end

    if input_only? do
      peer = Map.fetch!(claim.call.plan.participants, claim.call.plan.entry_receiver)

      assert {:ok, peer_command} =
               AttachConnection.new(
                 tenant_id: tenant.key,
                 actor_id: claim.call.plan.actor_id,
                 room_id: prepared.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: peer.participant_id,
                 connection_id: "diagnostic-peer",
                 deadline: DateTime.add(DateTime.utc_now(), 20, :second)
               )

      peer_connection =
        start_supervised!(
          Supervisor.child_spec(
            {SpeechConnection, command: peer_command, observer: self()},
            id: :diagnostic_peer
          )
        )

      assert {:ok, _} = SpeechConnection.attach(peer_connection)
      assert_receive {:scribe_started, peer_wire}, 5_000

      :ok =
        Wire.deliver_frame(
          peer_wire,
          JSON.encode!(%{
            "message_type" => "session_started",
            "session_id" => "synthetic-peer",
            "config" => echoed_settings()
          })
        )

      assert_receive {:configured_speech_ready, ^peer_connection}, 5_000

      send(
        self(),
        {:diagnostic_peer, peer_connection, SpeechConnection.attachment(peer_connection),
         peer_wire, peer_command}
      )
    end

    if sts_mode do
      ready_room = prepared.room_id
      assert_receive {:test_call_ready, ^ready_room}, 5_000
    else
      assert_receive {:configured_speech_ready, ^connection}, 5_000
    end

    if two_inputs? do
      guest = Map.fetch!(claim.call.plan.participants, "guest")

      assert {:ok, join} =
               JoinParticipant.new(
                 tenant_id: tenant.key,
                 actor_id: claim.call.plan.actor_id,
                 room_id: prepared.room_id,
                 participant_id: guest.participant_id,
                 role: :human,
                 deadline: DateTime.add(DateTime.utc_now(), 20, :second)
               )

      assert {:ok, _} = CallEngine.join_participant(join)

      assert {:ok, guest_command} =
               AttachConnection.new(
                 tenant_id: tenant.key,
                 actor_id: claim.call.plan.actor_id,
                 room_id: prepared.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: guest.participant_id,
                 connection_id: "diagnostic-guest",
                 deadline: DateTime.add(DateTime.utc_now(), 20, :second)
               )

      guest_connection =
        start_supervised!(
          Supervisor.child_spec(
            {SpeechConnection, command: guest_command, observer: self(), audit_events?: :scoped},
            id: {:speech_connection, prepared.room_id, "diagnostic-guest"}
          )
        )

      assert {:ok, _} = SpeechConnection.attach(guest_connection)
      assert_receive {:scribe_started, guest_wire}, 5_000

      :ok =
        Wire.deliver_frame(
          guest_wire,
          JSON.encode!(%{
            "message_type" => "session_started",
            "session_id" => "synthetic-guest",
            "config" => echoed_settings()
          })
        )

      assert_receive {:configured_speech_ready, ^guest_connection}, 5_000
      agent = Map.fetch!(claim.call.plan.participants, claim.call.plan.entry_receiver)
      send(self(), {:control_trace_agent, guest_connection, agent.participant_id})

      send(
        self(),
        {:diagnostic_extra_input, prepared.room_id,
         {claim.call, guest_connection, SpeechConnection.attachment(guest_connection), guest_wire,
          guest_command}}
      )
    end

    {claim.call, connection, SpeechConnection.attachment(connection), wire, command}
  end

  defp specialist_request do
    deadline = System.monotonic_time(:millisecond) + 2_000
    specialist_request(deadline)
  end

  defp specialist_request(deadline) do
    receive do
      {:test_agent_runtime_stream, provider, request} ->
        if hd(request.messages).content =~ "Handle specialist requests." do
          {provider, request}
        else
          {:ok, response} =
            Vxpipe.AgentRuntime.ModelResponse.new(
              text:
                ~s({"type":"participant_message","participant_id":"agent","agent_mode":"listener","message":null})
            )

          send(provider, {:test_agent_runtime_response, {:ok, response}})
          specialist_request(deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("specialist did not receive the input")
    end
  end

  defp external_turn_text(index, turn), do: "External PCM input #{index + 1}, turn #{turn}."

  defp external_pcm_loop(state) do
    complete? =
      state.exited? and state.report != nil and
        Enum.all?(state.inputs, fn {_index, input} ->
          input.completed == input.expected_turns and
            length(input.received) == input.expected_frames
        end)

    if complete?, do: state, else: external_pcm_receive(state)
  end

  defp external_pcm_receive(state) do
    port = state.port

    receive do
      {^port, {:data, <<0, json::binary>>}} ->
        external_pcm_loop(%{state | manifest: Jason.decode!(json)})

      {^port, {:data, <<1, index::16, sequence::32, pcm::binary-size(1024)>>}} ->
        input = Map.fetch!(state.inputs, index)
        assert sequence == input.frames

        if map_size(state.inputs) > 1 do
          <<source_marker::little-signed-16, _::binary>> = pcm
          assert source_marker == index + 1
        end

        frame = audio_frame(input.identity, input.epoch, sequence, sequence * 512, pcm)
        ingress_us = System.monotonic_time(:microsecond)
        assert :ok = CallEngine.push_audio(input.attachment, frame)

        updated = %{
          input
          | frames: sequence + 1,
            offered: [pcm | input.offered],
            ingress_times: Map.put(input.ingress_times, sequence, ingress_us)
        }

        external_pcm_loop(%{state | inputs: Map.put(state.inputs, index, updated)})

      {^port, {:data, <<3, json::binary>>}} ->
        resource = Jason.decode!(json)
        IO.puts("DIAGNOSTIC_RESOURCE_SAMPLE " <> json)

        started =
          if resource["sample"]["interval_start"],
            do: System.monotonic_time(:microsecond),
            else: state.measurement_started_us

        external_pcm_loop(%{
          state
          | resources: [resource | state.resources],
            measurement_started_us: started
        })

      {^port, {:data, <<2, json::binary>>}} ->
        external_pcm_loop(%{state | report: Jason.decode!(json)})

      {^port, {:exit_status, status}} ->
        assert status == 0
        external_pcm_loop(%{state | exited?: true})

      {:scribe_audio, wire, sequence, pcm, provider_us} ->
        index = Map.fetch!(state.wire_indices, wire)
        input = Map.fetch!(state.inputs, index)
        received = [pcm | input.received]
        count = length(received)
        assert count <= input.expected_frames
        assert sequence == count - 1
        ingress_us = Map.fetch!(input.ingress_times, sequence)
        assert provider_us >= ingress_us
        receipt = %{sequence: sequence, ingress_us: ingress_us, provider_us: provider_us}

        turn =
          Vxpipe.Console.Test.DiagnosticsSchedule.turn_at(
            index,
            count,
            state.rooms,
            state.inputs_per_room,
            state.workload
          )

        settlement_at = System.monotonic_time(:microsecond)

        settlements =
          if turn do
            emit_scribe_turn(wire, external_turn_text(index, turn))
            [{count, turn} | input.settlements]
          else
            input.settlements
          end

        times =
          if turn,
            do: Map.put(input.settlement_times, turn, settlement_at),
            else: input.settlement_times

        updated = %{
          input
          | received: received,
            settlements: settlements,
            settlement_times: times,
            ingress_latency: [receipt | input.ingress_latency]
        }

        external_pcm_loop(%{state | inputs: Map.put(state.inputs, index, updated)})

      {:vxpipe_event, %CallEngine.Event.AgentTurnInterrupted{} = event} ->
        source = Map.fetch!(state.source_indices, {event.room_id, event.source_participant_id})

        interrupter =
          Map.fetch!(state.source_indices, {event.room_id, event.interrupted_by_participant_id})

        flunk(
          "external workload response for input #{source} interrupted by input #{interrupter}"
        )

      {:vxpipe_event, %CallEngine.Event.AgentTurnCompleted{} = event} ->
        index = Map.fetch!(state.source_indices, {event.room_id, event.source_participant_id})
        input = Map.fetch!(state.inputs, index)
        assert event.source_participant_id == input.identity.participant_id
        assert input.completed < input.expected_turns
        refute Map.has_key?(input.completion_times, event.correlation_id)

        updated = %{
          input
          | completed: input.completed + 1,
            completion_times:
              Map.put(
                input.completion_times,
                event.correlation_id,
                System.monotonic_time(:microsecond)
              )
        }

        external_pcm_loop(%{state | inputs: Map.put(state.inputs, index, updated)})
    after
      5_000 ->
        progress =
          Map.new(state.inputs, fn {index, input} ->
            {index,
             %{frames: input.frames, received: length(input.received), completed: input.completed}}
          end)

        flunk(
          "external PCM workload did not complete: #{inspect(progress)}; generator exited: #{state.exited?}"
        )
    end
  end

  defp send_audio(attachment, identity, epoch, sequence, timestamp, pcm) do
    assert :ok =
             CallEngine.push_audio(
               attachment,
               audio_frame(identity, epoch, sequence, timestamp, pcm)
             )
  end

  defp audio_frame(identity, epoch, sequence, timestamp, pcm) do
    %AudioFrame{
      tenant_id: identity.tenant_id,
      room_id: identity.room_id,
      incarnation_id: identity.incarnation_id,
      participant_id: identity.participant_id,
      connection_id: identity.connection_id,
      source_epoch: epoch,
      track_id: "configured-speech",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: sequence,
      timestamp: timestamp,
      payload: pcm,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  # Real input continues while discovery scans rooms; one early frame is not a
  # readiness barrier. Keep receipt time and sample time aligned during discovery.
  defp discover_with_audio(attachment, identity, epoch, wire, sequence \\ 0) do
    deadline = System.monotonic_time(:millisecond) + 3_000
    discover_with_audio(attachment, identity, epoch, wire, sequence, deadline)
  end

  defp discover_with_audio(attachment, identity, epoch, wire, sequence, deadline) do
    receive do
      {:scribe_observing, ^wire, _} -> sequence
    after
      0 ->
        assert System.monotonic_time(:millisecond) < deadline,
               "No observer: #{inspect(RoomService.status(RoomService.address(identity)))}"

        _ = RoomService.scan(RoomService.address(identity))
        send_audio(attachment, identity, epoch, sequence, sequence * 512, <<0::size(8192)>>)
        pace(32)
        discover_with_audio(attachment, identity, epoch, wire, sequence + 1, deadline)
    end
  end

  defp pace(ms) do
    ref = make_ref()
    Process.send_after(self(), {:audio_pace, ref}, ms)
    assert_receive {:audio_pace, ^ref}, ms + 1_000
  end

  defp await(fun, timeout \\ 2_000),
    do: await_until(fun, System.monotonic_time(:millisecond) + timeout)

  defp await_until(fun, deadline) do
    case fun.() do
      result when result not in [false, nil] ->
        result

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "diagnostic observation timed out"
        pace(10)
        await_until(fun, deadline)
    end
  end

  defp echoed_settings,
    do: %{
      "model_id" => "scribe_v2_realtime",
      "sample_rate" => 16_000,
      "audio_format" => "pcm_16000",
      "commit_strategy" => "vad",
      "vad_silence_threshold_secs" => 1.5,
      "vad_threshold" => 0.4,
      "min_speech_duration_ms" => 100,
      "min_silence_duration_ms" => 100,
      "keepalive_interval_ms" => 500
    }

  defp operator do
    role = Repo.get_by!(IdentityRole, kind: "admin")
    id = Ecto.UUID.generate()

    user =
      Repo.insert!(
        IdentityUser.changeset(%IdentityUser{}, %{
          public_id: id,
          email: "#{id}@example.test",
          normalized_email: "#{id}@example.test",
          password_hash: "synthetic",
          role_id: role.id
        })
      )

    now = DateTime.utc_now()

    session =
      Repo.insert!(
        IdentitySession.changeset(%IdentitySession{}, %{
          public_id: Ecto.UUID.generate(),
          user_id: user.id,
          token_digest: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
          issued_at: now,
          expires_at: DateTime.add(now, 600)
        })
      )

    struct(Vxpipe.Identity.Principal,
      account_kind: :admin,
      user_public_id: user.public_id,
      session_public_id: session.public_id,
      role_public_id: role.public_id,
      role_revision: role.revision
    )
  end
end
