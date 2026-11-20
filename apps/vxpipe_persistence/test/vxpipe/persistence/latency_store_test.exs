defmodule Vxpipe.Persistence.LatencyStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, LatencyRun, TurnDiagnostic}
  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, LatencyStore, Repo}
  alias Vxpipe.Persistence.Schema.Call
  @now ~U[2026-11-19 12:00:00.000000Z]

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}},
      now: @now
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Archive binding", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    source = %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }

    {:ok, draft} = Calls.save_call_spec(tenant.key, source, options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(actor, tenant.key, published.call_spec_id, %{}, nil, nil, options)

    {:ok, token} = Calls.issue_call_join_token(actor, tenant.key, call.id, nil, options)
    scope = %{tenant_key: tenant.key, call_id: call.id, participant_key: token.participant_key}
    {:ok, claim} = Calls.claim_join_token(token.secret, scope, options)
    {:ok, :admit, _binding} = Calls.bind_call_admission(claim, "inc-1", options)
    %{call: claim.call, claim: claim, options: options}
  end

  test "run and turn evidence round trips through durable storage", %{call: call} do
    run = run(call)
    turn = turn(run)
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    assert {:ok, ^turn} = put_turn(run, turn)
    assert {:ok, ^run} = LatencyStore.fetch_run(Repo, run.tenant_key, run.call_id, run.id)

    assert {:ok, [^turn]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)
  end

  test "barge-in evidence survives durable revisions while legacy absence remains nil", %{
    call: call
  } do
    run = run(call)
    original = turn(run)
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    assert {:ok, ^original} = put_turn(run, original)
    import Ecto.Query

    from(t in Vxpipe.Persistence.Schema.TurnDiagnostic, where: t.turn_id == ^original.turn_id)
    |> Repo.update_all(
      set: [
        record: Map.delete(Vxpipe.Persistence.LatencyRecordCodec.encode(original), "barge_in")
      ]
    )

    assert {:ok, [legacy]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)

    assert Map.get(legacy, :barge_in) == nil

    evidence = Vxpipe.Calls.TestLatencyRecords.barge_in()

    attributes =
      original |> Map.from_struct() |> Map.drop([:durations_us, :metric_reasons, :quality])

    assert {:ok, updated} =
             TurnDiagnostic.new(Map.merge(attributes, %{revision: 2, barge_in: evidence}))

    assert {:ok, ^updated} = put_turn(run, updated)

    assert {:ok, [^updated]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)

    [entry] = evidence.entries
    missing = %{entry | speech_started_us: nil, duration_us: nil, reasons: [:missing_evidence]}
    revised = %{evidence | entries: [missing], omitted_count: 2, reasons: [:entry_limit]}

    assert {:ok, incomplete} =
             TurnDiagnostic.new(Map.merge(attributes, %{revision: 3, barge_in: revised}))

    assert {:ok, ^incomplete} = put_turn(run, incomplete)

    assert {:ok, [^incomplete]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)

    assert {:error, :stale_revision} = put_turn(run, updated)
  end

  test "versioned turn and unattached segments survive storage revisions and legacy reads", %{
    call: call
  } do
    segment = %{
      epoch: 0,
      start_sample: 0,
      end_sample: 512,
      start_us: 0,
      end_us: 32_000,
      start_confirmed_us: 96_000,
      end_confirmed_us: 544_000,
      uncertainty_us: 100,
      reasons: []
    }

    evidence = %{version: 1, entries: [segment], omitted_count: 1, reasons: [:segment_limit]}
    original = run(call)
    assert {:ok, ^original} = LatencyStore.put_run(Repo, original)
    old_turn = turn(original)
    assert {:ok, ^old_turn} = put_turn(original, old_turn)
    # Simulate a pre-extension stored record: absence is not an empty observed list.
    import Ecto.Query

    from(r in Vxpipe.Persistence.Schema.LatencyRun, where: r.public_id == ^original.id)
    |> Repo.update_all(
      set: [
        record:
          Map.delete(
            Vxpipe.Persistence.LatencyRecordCodec.encode(original),
            "unattached_segments"
          )
      ]
    )

    from(t in Vxpipe.Persistence.Schema.TurnDiagnostic, where: t.turn_id == ^old_turn.turn_id)
    |> Repo.update_all(
      set: [
        record:
          Map.delete(Vxpipe.Persistence.LatencyRecordCodec.encode(old_turn), "acoustic_segments")
      ]
    )

    assert {:ok, ^original} =
             LatencyStore.fetch_run(Repo, original.tenant_key, original.call_id, original.id)

    assert {:ok, [^old_turn]} =
             LatencyStore.list_turns(
               Repo,
               original.tenant_key,
               original.call_id,
               original.id,
               50,
               nil
             )

    revised_run = %{original | revision: 2, unattached_segments: evidence}
    revised_turn = %{old_turn | revision: 2, acoustic_segments: evidence}
    assert {:ok, ^revised_run} = LatencyStore.put_run(Repo, revised_run)
    assert {:ok, ^revised_turn} = put_turn(revised_run, revised_turn)

    assert {:ok, ^revised_run} =
             LatencyStore.fetch_run(Repo, original.tenant_key, original.call_id, original.id)

    assert {:ok, [^revised_turn]} =
             LatencyStore.list_turns(
               Repo,
               original.tenant_key,
               original.call_id,
               original.id,
               50,
               nil
             )

    assert {:error, :stale_revision} = put_turn(original, old_turn)
  end

  test "provider acknowledgements survive storage and cannot change with a later revision", %{
    call: call
  } do
    run = run(call)

    acknowledgement = %{
      model_id: "scribe_v2_realtime",
      sample_rate: 16_000,
      audio_format: "pcm_16000",
      commit_strategy: :vad,
      vad_silence_threshold_secs: 1.5,
      vad_threshold: 0.4,
      min_speech_duration_ms: 100,
      min_silence_duration_ms: 100,
      keepalive_interval_ms: 500
    }

    profile = Map.put(run.profile, :provider_acknowledgement, acknowledgement)
    assert {:ok, run} = LatencyRun.new(Map.from_struct(%{run | profile: profile}))
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    assert {:ok, ^run} = LatencyStore.fetch_run(Repo, run.tenant_key, run.call_id, run.id)
    changed = put_in(profile, [:provider_acknowledgement, :vad_threshold], 0.45)

    assert {:error, :run_identity_conflict} =
             LatencyStore.put_run(Repo, %{run | revision: 2, profile: changed})
  end

  test "same revision is idempotent but conflicting and stale updates are rejected", %{call: call} do
    run = run(call)
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    conflicting = %{run | heartbeat_at: DateTime.add(@now, 1, :second)}
    assert {:error, :revision_conflict} = LatencyStore.put_run(Repo, conflicting)
    updated = %{conflicting | revision: 2}
    assert {:ok, ^updated} = LatencyStore.put_run(Repo, updated)
    assert {:error, :stale_revision} = LatencyStore.put_run(Repo, run)
    turn = turn(run)
    assert {:ok, ^turn} = put_turn(run, turn)
    assert {:ok, ^turn} = put_turn(run, turn)
    changed = %{turn | provider_turn_id: "provider-1"}
    assert {:error, :revision_conflict} = put_turn(run, changed)
    revised = %{changed | revision: 2}
    assert {:ok, ^revised} = put_turn(run, revised)
    assert {:error, :stale_revision} = put_turn(run, turn)
  end

  test "tenant, room and incarnation mismatches cannot create or read evidence", %{
    call: call,
    options: options
  } do
    {:ok, foreign, _key} = Administration.bootstrap_tenant("Foreign tenant", [:calls], options)
    run = run(call)

    assert {:error, :call_not_found} =
             LatencyStore.put_run(Repo, %{run | tenant_key: foreign.key})

    assert {:error, :call_room_mismatch} =
             LatencyStore.put_run(Repo, %{run | room_id: Ecto.UUID.generate()})

    assert {:error, :call_incarnation_mismatch} =
             LatencyStore.put_run(Repo, %{run | incarnation_id: "other"})

    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)

    assert {:error, :call_not_found} =
             LatencyStore.fetch_run(Repo, foreign.key, run.call_id, run.id)

    assert {:error, :call_not_found} =
             LatencyStore.list_turns(Repo, foreign.key, run.call_id, run.id, 50, nil)

    assert {:error, :call_not_found} =
             LatencyStore.put_turn(Repo, foreign.key, run.call_id, run.incarnation_id, turn(run))

    assert {:error, :call_incarnation_mismatch} =
             LatencyStore.put_turn(Repo, run.tenant_key, run.call_id, "other", turn(run))
  end

  test "missing runs and mismatched source evidence are rejected", %{call: call} do
    run = run(call)
    turn = turn(run)
    assert {:error, :latency_run_not_found} = put_turn(run, turn)
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    assert {:error, :diagnostic_source_mismatch} = put_turn(run, %{turn | clock_id: "other"})
    assert {:error, :diagnostic_source_mismatch} = put_turn(run, %{turn | source_epoch: "other"})
  end

  test "deletion cascades and late writes cannot resurrect a call", %{call: call} do
    run = run(call)
    assert {:ok, ^run} = LatencyStore.put_run(Repo, run)
    assert {:ok, _} = put_turn(run, turn(run))
    Repo.get_by!(Call, public_id: call.id) |> Repo.delete!()
    assert {:error, :call_not_found} = LatencyStore.put_run(Repo, run)
    assert {:error, :call_not_found} = put_turn(run, turn(run))
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM call_latency_runs")
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM call_turn_diagnostics")
  end

  test "identity and profile are immutable and terminal runs never reopen", %{call: call} do
    run = run(call)
    assert {:ok, _} = LatencyStore.put_run(Repo, run)

    assert {:error, :run_identity_conflict} =
             LatencyStore.put_run(Repo, %{run | revision: 2, settings_revision: 2})

    closed = %{run | revision: 2, state: :closed, closed_at: @now}
    assert {:ok, ^closed} = LatencyStore.put_run(Repo, closed)
    assert {:error, :run_closed} = LatencyStore.put_run(Repo, %{run | revision: 3})
  end

  test "cursor pages are bounded and stable", %{call: call} do
    run = run(call)
    assert {:ok, _} = LatencyStore.put_run(Repo, run)

    for id <- ["turn-c", "turn-a", "turn-b"],
        do: assert({:ok, _} = put_turn(run, %{turn(run) | turn_id: id}))

    assert {:ok, [a, b]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 2, nil)

    assert [a.turn_id, b.turn_id] == ["turn-a", "turn-b"]

    assert {:ok, [c]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 2, b.turn_id)

    assert c.turn_id == "turn-c"

    assert {:error, :invalid_page} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 101, nil)
  end

  test "full report aggregates exclude missing evidence and separate profiles", %{call: call} do
    run = run(call)
    assert {:ok, _} = LatencyStore.put_run(Repo, run)

    for {id, end_us} <- [{"a", 1_100_000}, {"b", 1_300_000}, {"c", nil}] do
      attrs =
        turn(run) |> Map.from_struct() |> Map.drop([:durations_us, :metric_reasons, :quality])

      landmarks =
        if end_us, do: %{acoustic_end: 1_000_000, provider_end_received: end_us}, else: %{}

      {:ok, record} = TurnDiagnostic.new(%{attrs | turn_id: id, landmarks_us: landmarks})
      assert {:ok, _} = put_turn(run, record)
    end

    other = %{run | id: "run-2", profile: %{run.profile | model: "another-model"}}
    assert {:ok, _} = LatencyStore.put_run(Repo, other)
    assert {:ok, _} = put_turn(other, turn(other))

    assert {:ok, [_only_one]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 1, nil)

    assert {:ok, groups} = LatencyStore.summarize(Repo, run.tenant_key, run.call_id)

    metric =
      Enum.find(
        groups,
        &(&1.metric == "speech_end_to_provider_end" and
            &1.profile["model"] == "scribe_v2_realtime")
      )

    assert metric.valid_count == 2
    assert metric.excluded_count == 1
    assert metric.p50_us == 200_000
    assert metric.p95_us == 290_000
    assert Enum.count(groups, &(&1.metric == "speech_end_to_provider_end")) == 2
    assert {:error, :call_not_found} = LatencyStore.summarize(Repo, "foreign", run.call_id)
  end

  test "invalid forged records are rejected without a database write", %{call: call} do
    run = run(call)
    assert {:ok, _} = LatencyStore.put_run(Repo, run)
    forged = %{turn(run) | landmarks_us: %{"private" => "payload"}}
    assert {:error, :invalid_turn_diagnostic} = put_turn(run, forged)
    assert {:ok, []} = LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)
  end

  test "database unavailability is a diagnostic error rather than a caller crash", %{call: call} do
    unavailable =
      start_supervised!(
        {Repo,
         name: __MODULE__.UnavailableRepo,
         url: nil,
         hostname: "127.0.0.1",
         port: 1,
         database: "unavailable",
         username: "unavailable",
         password: nil,
         socket_dir: nil,
         pool: DBConnection.ConnectionPool,
         pool_size: 1,
         timeout: 100,
         connect_timeout: 100,
         queue_target: 10,
         queue_interval: 10}
      )

    previous = Repo.put_dynamic_repo(unavailable)

    try do
      assert {:error, :diagnostics_unavailable} = LatencyStore.put_run(Repo, run(call))
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  test "run timestamps must use the declared UTC clock before persistence", %{call: call} do
    run = run(call)
    non_utc = %{run.anchor_utc | utc_offset: 3_600, time_zone: "Europe/Paris", zone_abbr: "CET"}

    assert {:error, :invalid_latency_run} =
             LatencyStore.put_run(Repo, %{run | anchor_utc: non_utc, heartbeat_at: non_utc})
  end

  test "constructor-valid 256-byte run identities round trip through storage", %{call: call} do
    attrs = run(call) |> Map.from_struct() |> Map.put(:id, String.duplicate("r", 256))
    assert {:ok, record} = LatencyRun.new(attrs)
    assert {:ok, ^record} = LatencyStore.put_run(Repo, record)

    assert {:ok, ^record} =
             LatencyStore.fetch_run(Repo, record.tenant_key, record.call_id, record.id)
  end

  test "constructor-valid 256-byte turn identities round trip through storage", %{call: call} do
    run = run(call)
    assert {:ok, _} = LatencyStore.put_run(Repo, run)

    attrs =
      turn(run)
      |> Map.from_struct()
      |> Map.drop([:durations_us, :metric_reasons, :quality])
      |> Map.put(:turn_id, String.duplicate("t", 256))

    assert {:ok, record} = TurnDiagnostic.new(attrs)
    assert {:ok, ^record} = put_turn(run, record)

    assert {:ok, [^record]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)
  end

  test "constructor-valid second-precision UTC timestamps round trip through storage", %{
    call: call
  } do
    timestamp = DateTime.truncate(@now, :second)

    attrs =
      run(call)
      |> Map.from_struct()
      |> Map.merge(%{anchor_utc: timestamp, heartbeat_at: timestamp})

    assert {:ok, record} = LatencyRun.new(attrs)
    assert {:ok, ^record} = LatencyStore.put_run(Repo, record)

    assert {:ok, ^record} =
             LatencyStore.fetch_run(Repo, record.tenant_key, record.call_id, record.id)
  end

  test "run coverage pages count all durable turns and preserve missing collection", %{call: call} do
    run = run(call)

    assert {:ok, %{entries: [], next_cursor: nil}} =
             LatencyStore.list_runs(Repo, run.tenant_key, run.call_id, 1, nil)

    for id <- ["run-a", "run-b"] do
      record = %{run | id: id}
      assert {:ok, _} = LatencyStore.put_run(Repo, record)

      for turn_id <- ["turn-a", "turn-b"],
          do: assert({:ok, _} = put_turn(record, %{turn(record) | turn_id: turn_id}))
    end

    assert {:ok, %{entries: [%{run: first, stored_turns: 2}], next_cursor: "run-a"}} =
             LatencyStore.list_runs(Repo, run.tenant_key, run.call_id, 1, nil)

    assert first.id == "run-a"

    assert {:ok, %{entries: [%{run: last, stored_turns: 2}], next_cursor: nil}} =
             LatencyStore.list_runs(Repo, run.tenant_key, run.call_id, 1, "run-a")

    assert last.id == "run-b"

    assert {:error, :call_not_found} =
             LatencyStore.list_runs(Repo, "foreign", run.call_id, 50, nil)

    assert {:error, :invalid_page} =
             LatencyStore.list_runs(Repo, run.tenant_key, run.call_id, 101, nil)
  end

  test "live collector revisions survive collector and writer shutdown", %{call: call} do
    alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
    alias Vxpipe.Calls.Diagnostics.Collector
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)

    start_supervised!(
      {Vxpipe.Calls.Diagnostics.Supervisor,
       name: __MODULE__.WritersRoot,
       writer_supervisor: __MODULE__.Writers,
       task_supervisor: __MODULE__.Tasks}
    )

    generation = make_ref()
    reference = make_ref()
    run = run(call)

    collector =
      start_supervised!(
        {Collector,
         run: run,
         generation: generation,
         origin_us: 0,
         owner: self(),
         coordinator: self(),
         settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
         writer_supervisor: __MODULE__.Writers,
         utc_now: fn -> @now end,
         writer_options: [
           repository: {LatencyStore, Repo},
           task_supervisor: __MODULE__.Tasks,
           observer: self()
         ]}
      )

    capture = Collector.handoff(collector)
    assert_receive {:diagnostic_settled, writer, :stored}, 1_000

    for packet <- [
          {:provider_sample_mapping, generation, 0, 0},
          {:provider_landmark, generation, reference, :provider_end_evidence, 70_000, 3_000},
          {:room_turn_completed, generation, reference, "live-turn", "command", 71_000}
        ],
        do: assert(:ok == CaptureHandoff.offer(capture, packet))

    assert_receive {:diagnostic_settled, ^writer, :stored}, 1_000

    assert {:ok, [%{revision: first_revision, durations_us: %{speech_end_to_provider_end: nil}}]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)

    for packet <- [
          {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
          {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 90_000, 1_000, nil},
          {:acoustic_progress, 0, 0, 3_072}
        ],
        do: assert(:ok == CaptureHandoff.offer(capture, packet))

    assert_receive {:diagnostic_settled, ^writer, :stored}, 1_000
    writer_monitor = Process.monitor(writer)
    assert :ok = Collector.close(collector, :call_ended)
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :normal}, 1_000
    assert {:ok, stored} = LatencyStore.fetch_run(Repo, run.tenant_key, run.call_id, run.id)
    assert stored.state == :closed
    assert stored.counts.observed_turns == 1

    assert {:ok, [turn]} =
             LatencyStore.list_turns(Repo, run.tenant_key, run.call_id, run.id, 50, nil)

    assert turn.revision > first_revision
    assert turn.durations_us.speech_end_to_provider_end == 30_000
    assert turn.durations_us.observer_confirmation == 50_000
  end

  defp put_turn(run, turn),
    do: LatencyStore.put_turn(Repo, run.tenant_key, run.call_id, run.incarnation_id, turn)

  defp turn(run) do
    {:ok, turn} =
      TurnDiagnostic.new(%{
        run_id: run.id,
        turn_id: "turn-1",
        stt_allocation_id: "allocation-1",
        clock_id: run.clock_id,
        source_epoch: run.source_epoch,
        landmarks_us: %{acoustic_end: 1_000_000, provider_end_received: 1_400_000}
      })

    turn
  end

  defp run(call) do
    {:ok, run} =
      LatencyRun.new(%{
        id: "run-1",
        tenant_key: call.tenant_key,
        call_id: call.id,
        room_id: call.room_id,
        incarnation_id: "inc-1",
        participant_id: "caller",
        connection_id: "connection-1",
        source_epoch: "source-1",
        clock_id: "clock-1",
        settings_revision: 1,
        anchor_utc: @now,
        profile: %{
          provider: "elevenlabs",
          model: "scribe_v2_realtime",
          commit_strategy: :vad,
          inference_source: :benchmark_only,
          vad_model: "silero_v6.2.3",
          algorithm_version: 1,
          sample_rate: 16_000,
          onset_threshold: 0.5,
          offset_threshold: 0.35,
          onset_frames: 4,
          offset_frames: 16
        }
      })

    run
  end
end
