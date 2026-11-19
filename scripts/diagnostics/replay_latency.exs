defmodule Vxpipe.Tools.LatencyReplay do
  alias Vxpipe.CallEngine.Diagnostics.{AcousticReplay, ReplayReport, ScribeReplay}
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Silero}
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, LatencyRun, TurnDiagnostic}
  alias Vxpipe.Calls.Diagnostics.{Coverage, Handoff, Writer}
  alias Vxpipe.Calls.Diagnostics.Supervisor, as: WriterPool
  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, LatencyStore, Repo}
  alias Vxpipe.Persistence.Schema.{Call, CallFact, Tenant}

  def main([mode]) when mode in ["write", "read"] do
    Logger.configure(level: :warning)
    {:ok, _} = Application.ensure_all_started(:vxpipe_calls)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    database = Keyword.fetch!(Repo.config(), :database)

    unless Regex.match?(~r/^vxpipe_latency_replay_[0-9]+_[0-9]+$/, database),
      do: raise("Replay only operates on its isolated fixture databases")

    {:ok, _} = Repo.start_link()
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    if mode == "write", do: write()
    if mode == "read", do: read(database)
  end

  defp write do
    pcm =
      File.read!("apps/vxpipe_providers/test/fixtures/deepgram/short_answer_16k_mono_s16le.pcm")

    # Explicit synthetic trailing silence makes the final fixture boundary observable.
    padding = rem(1_024 - rem(byte_size(pcm), 1_024), 1_024)
    pcm = pcm <> :binary.copy(<<0>>, padding + 64 * 1_024)
    duration_us = (div(byte_size(pcm), 2) * 1_000_000) |> div(16_000)
    anchor = DateTime.add(DateTime.utc_now(), -duration_us - 1_000_000, :microsecond)
    call = prepare_call(anchor)
    {:ok, model} = Silero.load()

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {CapabilityTree, owner: self()},
          {WriterPool,
           name: __MODULE__.Pool,
           task_supervisor: __MODULE__.Tasks,
           writer_supervisor: __MODULE__.Writers}
        ], strategy: :one_for_one, name: __MODULE__.Supervisor)

    {CapabilityTree, tree, _, _} =
      Enum.find(Supervisor.which_children(supervisor), fn {id, _, _, _} ->
        id == CapabilityTree
      end)

    scope = CapabilityTree.scope(tree)

    for scenario <- [:complete, :missing_audio] do
      replay_case(call, model, scope, pcm, anchor, duration_us, scenario)
    end

    stored = Repo.get_by!(Call, public_id: call.id)

    Repo.update!(
      Ecto.Changeset.change(stored,
        state: :ended,
        started_at: anchor,
        ended_at: DateTime.add(anchor, duration_us, :microsecond)
      )
    )

    Supervisor.stop(supervisor)
    IO.puts("Stored two offline diagnostic scenarios without provider network calls.")
  end

  defp replay_case(call, model, scope, pcm, anchor, duration_us, scenario) do
    id = Atom.to_string(scenario)
    clock = "fixture-clock-" <> id
    source = "fixture-source-" <> id
    frames = frames(pcm, source)
    {:ok, reference} = AcousticReplay.run(model, frames, clock, source)

    {:speech_ended, endpoint} =
      reference.events |> Enum.filter(&match?({:speech_ended, _}, &1)) |> List.last()

    trace =
      if scenario == :missing_audio do
        {:ok, trace} =
          AcousticReplay.run(model, Enum.reject(frames, &(&1.sequence == 10)), clock, source)

        trace
      else
        reference
      end

    # Logical fixture timings, not measurements of the live provider.
    steps = [
      {endpoint.offset_us + 100_000, {:segment, "synthetic fixture"}},
      {endpoint.offset_us + 300_000, {:partial, ""}}
    ]

    {:ok, provider_turns} = ScribeReplay.run(scope, steps, pcm: pcm)
    {:ok, reports} = ReplayReport.build(clock, source, provider_turns, trace)
    [report] = reports
    expected = if scenario == :complete, do: 300_000, else: nil

    unless report.durations_us.speech_end_to_provider_end == expected,
      do: raise("Unexpected fixture timing result")

    {:ok, run} =
      LatencyRun.new(%{
        id: id,
        tenant_key: call.tenant_key,
        call_id: call.id,
        room_id: call.room_id,
        incarnation_id: "offline-replay",
        participant_id: "caller",
        connection_id: "offline-source",
        source_epoch: source,
        clock_id: clock,
        settings_revision: 1,
        anchor_utc: anchor,
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

    {:ok, writer} =
      WriterPool.start_writer(
        [
          repository: {LatencyStore, Repo},
          task_supervisor: __MODULE__.Tasks,
          attempt_timeout_ms: 5_000,
          drain_timeout_ms: 15_000
        ],
        __MODULE__.Writers
      )

    handoff = Writer.handoff(writer)
    :ok = Handoff.offer(handoff, {:run, run})

    for {report, index} <- Enum.with_index(reports, 1) do
      {:ok, turn} =
        TurnDiagnostic.new(%{
          run_id: id,
          turn_id: "turn-#{index}",
          stt_allocation_id: "offline-allocation-" <> id,
          clock_id: clock,
          source_epoch: source,
          landmarks_us: report.landmarks_us,
          acoustic_reason: report.acoustic_reason,
          acoustic_sample: report.acoustic_sample,
          uncertainty_us: report.uncertainty_us
        })

      :ok = Handoff.offer(handoff, {:turn, call.tenant_key, call.id, "offline-replay", turn})
    end

    ending = DateTime.add(anchor, duration_us, :microsecond)

    final = %{
      run
      | revision: 2,
        heartbeat_at: ending,
        closed_at: ending,
        state: if(scenario == :complete, do: :closed, else: :incomplete),
        reasons: if(scenario == :complete, do: [], else: [:audio_gap]),
        counts: %{
          observed_turns: length(reports),
          dropped_audio_frames: if(scenario == :complete, do: 0, else: 1),
          unmatched_provider_events: 0
        }
    }

    :ok = Handoff.offer(handoff, {:run, final})
    monitor = Process.monitor(writer)
    :ok = Writer.drain(writer)

    receive do
      {:DOWN, ^monitor, :process, ^writer, :normal} -> :ok
    after
      16_000 -> raise("Offline diagnostic drain did not finish")
    end

    unless Handoff.stats(handoff).discarded == 0,
      do: raise("Offline diagnostic writes were discarded")
  end

  defp frames(pcm, source) do
    chunks = for <<chunk::binary-size(1_024) <- pcm>>, do: chunk

    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      %{
        pcm: chunk,
        sample_timestamp: index * 512,
        sample_count: 512,
        sequence: index,
        received_offset_us: (index + 1) * 32_000,
        processed_offset_us: (index + 1) * 32_000,
        source_epoch: source
      }
    end)
  end

  defp prepare_call(anchor) do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}},
      now: anchor
    ]

    {:ok, tenant, key} =
      Administration.bootstrap_tenant("Offline diagnostic replay", [:calls], options)

    {:ok, principal} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    source = %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Synthetic offline fixture."}
      }
    }

    {:ok, draft} = Calls.save_call_spec(tenant.key, source, options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(principal, tenant.key, published.call_spec_id, %{}, nil, nil, options)

    {:ok, token} = Calls.issue_call_join_token(principal, tenant.key, call.id, nil, options)
    scope = %{tenant_key: tenant.key, call_id: call.id, participant_key: token.participant_key}
    {:ok, claim} = Calls.claim_join_token(token.secret, scope, options)
    {:ok, :admit, _} = Calls.bind_call_admission(claim, "offline-replay", options)
    claim.call
  end

  defp read(database) do
    [call] = Repo.all(Call)
    tenant = Repo.get!(Tenant, call.tenant_id)

    {:ok, %{entries: entries, next_cursor: nil}} =
      LatencyStore.list_runs(Repo, tenant.key, call.public_id, 100, nil)

    rows =
      Enum.map(entries, fn %{run: run, stored_turns: count} ->
        {:ok, turns} = LatencyStore.list_turns(Repo, tenant.key, call.public_id, run.id, 100, nil)

        %{
          scenario: run.id,
          coverage: Coverage.describe(run, count, DateTime.utc_now()),
          turns:
            Enum.map(turns, fn turn ->
              %{
                turn_id: turn.turn_id,
                quality: turn.quality,
                durations_us: turn.durations_us,
                acoustic_reason: turn.acoustic_reason
              }
            end)
        }
      end)

    unless length(rows) == 2, do: raise("Missing persisted fixture runs")

    output = %{
      synthetic_fixture: true,
      database: database,
      ordinary_call_facts: Repo.aggregate(CallFact, :count),
      scenarios: rows
    }

    json = JSON.encode!(output)
    path = Path.join(System.tmp_dir!(), database <> ".json")
    File.write!(path, json <> "\n")
    IO.puts(json)
    IO.puts("Persisted report: " <> path)
  end
end

Vxpipe.Tools.LatencyReplay.main(System.argv())
