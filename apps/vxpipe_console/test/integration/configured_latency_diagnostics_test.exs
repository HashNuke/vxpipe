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

  setup do
    parent = self()
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
    assert {:ok, %{enabled: true}} = DiagnosticsSettingsStore.update(operator(), true, 0)

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
       repository: {Vxpipe.Console.Test.HeldLatencyStore, {Repo, parent}},
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
         classify: fn model, stream, pcm ->
           if byte_size(pcm) == 1_024 do
             Silero.push(stream, model, pcm)
           else
             send(parent, {:classify, self(), byte_size(pcm)})

             receive do
               :finish -> Silero.push(stream, model, pcm)
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

    %{options: options}
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

  defp call(options) do
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
            credential_name: "diagnostic-scribe"
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
  defp discover_with_audio(attachment, identity, epoch, wire) do
    deadline = System.monotonic_time(:millisecond) + 3_000
    discover_with_audio(attachment, identity, epoch, wire, 0, deadline)
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
