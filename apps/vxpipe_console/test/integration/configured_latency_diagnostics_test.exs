defmodule Vxpipe.Console.Integration.ConfiguredLatencyDiagnosticsTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  @moduletag timeout: 30_000
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Diagnostics.{
    AgentRuntimeModelProvider,
    ModelFixture,
    SettingsSupervisor,
    SourceCoordinator
  }

  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Speech.Silero
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Console.Test.SpeechConnection

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
    enabled = Map.get(tags, :diagnostics_enabled, true)
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
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
      |> Keyword.put(:speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            wire_module: Wire,
            wire_options: [observer: parent],
            activity_options:
              if(matrix?,
                do: [
                  load: fn -> {:ok, :matrix_model} end,
                  classify: matrix_classifier(parent, :operational)
                ],
                else: []
              ),
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )

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
         if(matrix?,
           do: {LatencyStore, Repo},
           else: {Vxpipe.Console.Test.HeldLatencyStore, {Repo, parent}}
         ),
       writer_supervisor: __MODULE__.Writers,
       collector_supervisor: __MODULE__.Collectors,
       task_supervisor: __MODULE__.Writes,
       maximum_collectors: 1,
       source_options: [
         name: __MODULE__.Sources,
         workers: __MODULE__.Workers,
         inference: __MODULE__.Inference,
         tasks: __MODULE__.Tasks,
         runtime: __MODULE__.Runtime,
         coordinator: __MODULE__.Coordinator,
         poll_interval_ms: 250,
         classify:
           if(matrix?,
             do: matrix_classifier(parent, :benchmark),
             else: fn model, stream, pcm ->
               if byte_size(pcm) == 1_024 do
                 Silero.push(stream, model, pcm)
               else
                 send(parent, {:classify, self(), byte_size(pcm)})

                 receive do
                   :finish -> Silero.push(stream, model, pcm)
                 end
               end
             end
           )
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

    %{options: options, settings_revision: settings_revision}
  end

  test "configured Scribe call persists pending timing then late acoustic confirmation", c do
    {call, _connection, attachment, wire, identity} = call(c.options)
    epoch = make_ref()
    sequence = discover_with_audio(attachment, identity, epoch, wire)
    sample_origin = sequence * 512

    await(fn -> SourceCoordinator.status(__MODULE__.Coordinator).active_sources == 1 end)

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
          _ = SourceCoordinator.scan(__MODULE__.Coordinator)
          assert SourceCoordinator.status(__MODULE__.Coordinator).active_sources == 0
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

        assert DynamicSupervisor.count_children(__MODULE__.Workers).active == 0
      end

      assert {:ok, %{entries: before_toggle}} =
               LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)

      off_pcm = :binary.copy(<<8, 0>>, 512)

      next_sequence =
        if @diagnostics do
          change_diagnostics(false, c.settings_revision)
          _ = SourceCoordinator.scan(__MODULE__.Coordinator)
          await_diagnostic_drain()
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

      _ = SourceCoordinator.scan(__MODULE__.Coordinator)
      await_diagnostic_drain()

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
      await_diagnostic_drain()

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

  defp change_diagnostics(enabled, revision) do
    assert {:ok, %{enabled: ^enabled, revision: next}} =
             DiagnosticsSettingsStore.update(operator(), enabled, revision)

    expected = {if(enabled, do: :enabled, else: :disabled), next}

    await(fn ->
      Vxpipe.CallEngine.Diagnostics.SettingsProjection.status(__MODULE__.Projection) == expected
    end)
  end

  defp await_diagnostic_drain do
    await(fn ->
      Enum.all?([__MODULE__.Workers, __MODULE__.Collectors, __MODULE__.Writers], fn supervisor ->
        DynamicSupervisor.count_children(supervisor).active == 0
      end)
    end)
  end

  defp matrix_classifier(parent, mode) do
    fn _model, stream, pcm ->
      send(parent, {:matrix_inference, mode, stream.samples, pcm})
      count = div(byte_size(pcm), 1_024)
      {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.0, count)}
    end
  end

  defp call(options, vad \\ false) do
    {:ok, tenant, key} = Administration.bootstrap_tenant("Diagnostic fixture", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    assert {:ok, _} =
             ProviderCredentials.provision(
               :platform,
               "elevenlabs",
               "diagnostic-scribe",
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
            credential_name: "diagnostic-scribe",
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

    connection = start_supervised!({SpeechConnection, command: command, observer: self()})
    assert {:ok, attachment} = SpeechConnection.attach(connection)

    on_exit(fn ->
      try do
        GenServer.stop(attachment.room_authority, :shutdown)
      catch
        :exit, _ -> :ok
      end
    end)

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

    assert_receive {:configured_speech_ready, ^connection}, 5_000
    {claim.call, connection, SpeechConnection.attachment(connection), wire, command}
  end

  defp send_audio(attachment, identity, epoch, sequence, timestamp, pcm) do
    assert :ok =
             CallEngine.push_audio(attachment, %AudioFrame{
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
             })
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
               "No observer: #{inspect(SourceCoordinator.status(__MODULE__.Coordinator))}"

        _ = SourceCoordinator.scan(__MODULE__.Coordinator)
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
