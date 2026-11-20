defmodule Vxpipe.Console.Test.LiveDiagnosticsBrowserScenario do
  @moduledoc "Tagged live Scribe/native VAD acceptance; model and TTS remain explicit fixtures."
  import ExUnit.Assertions
  import ExUnit.Callbacks
  import Phoenix.ConnTest
  alias Vxpipe.{Calls, CallEngine}
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Console.Test.{LiveDiagnosticsBrowserDriver, LiveDiagnosticsBrowserSite}

  alias Vxpipe.Persistence.{
    Repo,
    AccessKeyStore,
    CallStore,
    CallSpecStore,
    CredentialStore,
    CredentialKeyring,
    ProviderCredentialStore,
    DiagnosticsSettingsStore,
    LatencyStore
  }

  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentityUser, IdentitySession}
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  @endpoint Endpoint
  @email "live-diagnostics@example.test"
  @password "Fixture browser password 32!"

  def run!(operational?, key) do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)

    sandbox =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 300_000)

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)
    operator = identity!()
    assert {:ok, %{enabled: true}} = DiagnosticsSettingsStore.update(operator, true, 0)
    progress = start_supervised!({Agent, fn -> %{"phase" => "initial", "finished" => []} end})
    handler = {__MODULE__, self()}

    :ok =
      :telemetry.attach(
        handler,
        [:vxpipe, :test, :live_scribe_pcm],
        &__MODULE__.capture_pcm/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)
    mount = Endpoint.config(:gateway_mount)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, CallEngine.Application, original)
      Phoenix.Config.put(Endpoint, :gateway_mount, mount)
    end)

    runtime =
      original
      |> Keyword.update!(
        :agent_runtime,
        &Keyword.put(&1, :fixture, {CallEngine.TestAgentRuntimeModelProvider, [owner: self()]})
      )
      |> Keyword.put(:diagnostics, port: __MODULE__.Port)
      |> Keyword.put(:diagnostics_settings_loader, &DiagnosticsSettingsStore.snapshot/0)
      |> Keyword.put(:speech_to_text,
        providers: %{
          Vxpipe.Providers.ElevenLabs.STTSession => [
            enabled: true,
            wire_module: Vxpipe.Console.Test.LiveDiagnosticsScribeSocket,
            wire_options: [observer: self()]
          ]
        }
      )
      |> Keyword.put(:text_to_speech,
        providers: %{
          Vxpipe.Providers.Deepgram.TTSSession => [
            enabled: true,
            wire_module: CallEngine.TestTextToSpeechTransport,
            wire_options: [observer: self(), ready_on_start: true]
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, runtime)
    old_tool = Application.get_env(:vxpipe_call_engine, :blocking_tool_observer)
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> restore(:vxpipe_call_engine, :blocking_tool_observer, old_tool) end)

    start_supervised!(
      {Calls.Diagnostics.Supervisor,
       name: __MODULE__.Diagnostics,
       repository: {LatencyStore, Repo},
       writer_supervisor: __MODULE__.Writers,
       collector_supervisor: __MODULE__.Collectors,
       task_supervisor: __MODULE__.Writes,
       maximum_collectors: 1,
       source_options: [
         name: __MODULE__.Sources,
         inference: __MODULE__.Inference,
         tasks: __MODULE__.Tasks,
         runtime: __MODULE__.Runtime,
         port: __MODULE__.Port
       ]}
    )

    {:ok, keyring} =
      CredentialKeyring.new("fixture", %{"fixture" => :crypto.strong_rand_bytes(32)})

    options = [
      access_key_repository: {AccessKeyStore, Repo},
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      registries: %{host_tools: %{"wait_for_test" => CallEngine.TestBlockingTool}},
      speech_runtime: Keyword.take(runtime, [:speech_to_text, :text_to_speech]),
      publication_enabled: false
    ]

    options =
      Keyword.merge(options,
        admin_repository: {Vxpipe.Persistence.AdminStore, Repo},
        archive_repository: {Vxpipe.Persistence.ArchiveStore, Repo},
        artifact_repository: {Vxpipe.Persistence.ArtifactStore, Repo},
        usage_repository: {Vxpipe.Persistence.UsageStore, Repo},
        latency_repository: {LatencyStore, Repo},
        call_details_inspection_repository: {Vxpipe.Persistence.CallDetailsInspectionStore, Repo},
        inspection_repository: {Vxpipe.Persistence.InspectionStore, Repo},
        publication_repository: {Vxpipe.Persistence.CallDetailsPublicationStore, Repo},
        publication_source:
          {Vxpipe.Persistence.CallDetailsSource, [repo: Repo, recording: :unconfigured]}
      )

    original_calls = Application.get_env(:vxpipe_calls, Calls)
    Application.put_env(:vxpipe_calls, Calls, Keyword.merge(original_calls || [], options))
    on_exit(fn -> restore(:vxpipe_calls, Calls, original_calls) end)

    archive = [
      enabled: true,
      writer: {Vxpipe.Persistence.EctoStorage, options},
      maximum_pending_facts: 256,
      retry_delay_ms: 25,
      drain_timeout_ms: 5_000,
      source_policy: %{"revision" => 0}
    ]

    options = Keyword.merge(options, archive: archive, managed_cleanup: true)
    options = Keyword.put(options, :credential_source, {ProviderCredentialSource, options})

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Live diagnostics fixture", [:admin, :calls], options)

    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)

    for {provider, name, secret} <- [
          {"elevenlabs", "scribe", key},
          {"deepgram", "fixture-tts", "synthetic"}
        ] do
      assert {:ok, _} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 name,
                 "api_key",
                 %{"api_key" => secret},
                 options
               )
    end

    assert {:ok, revision} = Calls.save_call_spec(tenant.key, source(operational?), options)
    assert revision.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(
               tenant.key,
               revision.call_spec_id,
               revision.revision,
               options
             )

    [route] = published.routes

    Phoenix.Config.put(
      Endpoint,
      :gateway_mount,
      Vxpipe.Gateway.HTTP.Mount.init(
        call_admission: [enabled: true, backend: {Vxpipe.Gateway.CallAdmission, options}]
      )
    )

    server =
      start_supervised!(
        {Bandit,
         plug:
           {LiveDiagnosticsBrowserSite,
            %{
              owner: self(),
              progress: progress,
              assets: build_site!(),
              principal: principal,
              route: route.key,
              calls: options
            }},
         ip: {127, 0, 0, 1},
         port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    parent = self()
    browser_session = LiveDiagnosticsBrowserDriver.session()
    on_exit(fn -> LiveDiagnosticsBrowserDriver.close(browser_session) end)

    start_supervised!(
      {Task,
       fn ->
         try do
           send(
             parent,
             {:live_browser_finished,
              LiveDiagnosticsBrowserDriver.run!(
                "http://127.0.0.1:#{port}",
                @email,
                @password,
                browser_session,
                &ensure_secret_free!(&1, key)
              )}
           )
         rescue
           error -> send(parent, {:live_browser_failed, Exception.message(error)})
         end
       end}
    )

    state =
      loop(
        %{
          progress: progress,
          principal: principal,
          calls_options: options,
          call: nil,
          streams: %{},
          tool?: false,
          tool_executed?: false,
          phase_turns: %{},
          pcm_bytes: 0,
          tts_pending: %{},
          provider_profile: nil,
          browser: nil
        },
        System.monotonic_time(:millisecond) + 240_000
      )

    inspect_report!(state, operational?, key)
  end

  def capture_pcm(_event, %{bytes: bytes}, _metadata, observer),
    do: send(observer, {:live_scribe_pcm, bytes})

  defp loop(%{browser: evidence} = state, _deadline) when not is_nil(evidence), do: state

  defp loop(state, deadline) do
    receive do
      {:structured_browser_call, call} ->
        IO.puts("LIVE_DIAGNOSTICS_STAGE admitted")
        on_exit(fn -> end_call(call) end)

        Agent.update(
          state.progress,
          &Map.put(&1, "call", %{"id" => call.id, "tenant_key" => call.tenant_key})
        )

        loop(%{state | call: call}, deadline)

      {:structured_browser_control, %{"action" => "hangup"}} ->
        assert {:ok, %{status: status}} =
                 Vxpipe.Gateway.CallHangup.request(
                   state.principal,
                   state.call.tenant_key,
                   state.call.id,
                   state.calls_options
                 )

        assert status in ["ending", "ended"]
        send(self(), {:verify_hangup, System.monotonic_time(:millisecond) + 5_000})
        loop(state, deadline)

      {:verify_hangup, until} ->
        assert {:ok, stored} =
                 Calls.fetch_call(state.call.tenant_key, state.call.id, state.calls_options)

        if stored.state == :ended do
          assert stored.hangup_requested_at != nil
          Agent.update(state.progress, &Map.put(&1, "hung_up", true))
          IO.puts("LIVE_DIAGNOSTICS_STAGE durable_hangup")
        else
          assert System.monotonic_time(:millisecond) < until,
                 "Call did not reach durable ended state after production hangup"

          Process.send_after(self(), {:verify_hangup, until}, 25)
        end

        loop(state, deadline)

      {:structured_browser_control, %{"action" => "phase", "phase" => phase}} ->
        assert phase in ["normal", "pause", "barge_base", "barge", "tool"]
        IO.puts("LIVE_DIAGNOSTICS_STAGE " <> phase)
        Agent.update(state.progress, &Map.put(&1, "phase", phase))
        snapshot = CallEngine.RoomAuthority.snapshot(state.call.tenant_key, state.call.room_id)

        identity = %{
          tenant_id: state.call.tenant_key,
          room_id: state.call.room_id,
          incarnation_id: snapshot.incarnation_id
        }

        service = CallEngine.Diagnostics.RoomSupervisor.address(identity, :service)

        IO.puts(
          "LIVE_DIAGNOSTICS_SOURCE " <>
            JSON.encode!(CallEngine.Diagnostics.RoomService.status(service))
        )

        loop(state, deadline)

      {:test_agent_runtime_stream, provider, request} ->
        phase = Agent.get(state.progress, & &1["phase"])
        IO.puts("LIVE_DIAGNOSTICS_MODEL " <> phase)
        correlation = request.correlation

        identity =
          Map.take(
            Map.from_struct(correlation.tool_context),
            [
              :room_id,
              :incarnation_id,
              :source_participant_id,
              :connection_id,
              :agent_participant_id,
              :command_id,
              :correlation_id
            ]
          )

        prior = Map.get(state.phase_turns, phase)
        continuation? = prior != nil and prior != identity

        if continuation? do
          assert phase == "tool" and state.tool_executed?
          observation = List.last(request.messages)
          assert observation.origin == :engine
          payload = observation.content |> String.split("\n") |> List.last() |> JSON.decode!()
          assert payload["type"] == "tool_invocation_completion"
          assert payload["tool_name"] == "wait_for_test"

          assert Map.drop(prior, [:command_id, :correlation_id]) ==
                   Map.drop(identity, [:command_id, :correlation_id])
        end

        state = %{state | phase_turns: Map.put_new(state.phase_turns, phase, identity)}

        response =
          if phase == "tool" and not state.tool? do
            {:ok, tool} =
              Vxpipe.AgentRuntime.ToolCall.new(
                id: "fixture-tool",
                name: "wait_for_test",
                arguments: %{}
              )

            {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "", tool_calls: [tool])
            response
          else
            text =
              if phase == "tool",
                do:
                  ~s({"type":"participant_message","participant_id":"assistant","agent_mode":"listener","message":null}),
                else:
                  ~s({"type":"participant_message","participant_id":"assistant","agent_mode":"speaker","message":"Acknowledged."})

            {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: text)
            response
          end

        send(provider, {:test_agent_runtime_response, {:ok, response}})

        if phase == "tool" and continuation? do
          assert state.tool_executed?
          finished(state.progress, phase)
        end

        loop(%{state | tool?: state.tool? or phase == "tool"}, deadline)

      {:test_blocking_tool_started, tool} ->
        assert state.tool?
        send(tool, :release_test_tool)
        loop(%{state | tool_executed?: true}, deadline)

      {:test_tts_transport_started, _transport, _connection} ->
        IO.puts("LIVE_DIAGNOSTICS_STAGE fixture_tts_ready")
        loop(state, deadline)

      {:test_tts_control, transport, payload} ->
        phase = Agent.get(state.progress, & &1["phase"])

        case JSON.decode!(payload) do
          %{"type" => "Speak"} ->
            IO.puts("LIVE_DIAGNOSTICS_TTS " <> phase)
            id = "fixture-#{System.unique_integer([:positive])}"
            control(transport, %{type: "SpeechStarted", speech_id: id})
            send(self(), {:tone, transport, id})
            stream = %{id: id, left: if(phase == "barge_base", do: 750, else: 15), phase: phase}
            loop(%{state | streams: Map.put(state.streams, transport, stream)}, deadline)

          %{"type" => "Flush"} ->
            loop(state, deadline)

          %{"type" => "Interrupt"} ->
            stream = Map.fetch!(state.streams, transport)

            control(transport, %{
              type: "SpeechInterrupted",
              audio_played_ms: 0,
              text_spoken: "",
              text_remaining: "Acknowledged.",
              metadata: %{speech_id: stream.id}
            })

            loop(%{state | streams: Map.delete(state.streams, transport)}, deadline)

          %{"type" => "Close"} ->
            loop(state, deadline)

          _ ->
            flunk("Unexpected fixture speech control")
        end

      {:tone, transport, id} ->
        case Map.get(state.streams, transport) do
          %{id: ^id, left: 0} = stream ->
            control(transport, %{type: "SpeechMetadata", speech_id: id})
            finished(state.progress, stream.phase)
            loop(%{state | streams: Map.delete(state.streams, transport)}, deadline)

          %{id: ^id} = stream ->
            pcm =
              for n <- 0..959,
                  into: <<>>,
                  do:
                    <<round(4000 * :math.sin(2 * :math.pi() * 440 * n / 48_000))::little-signed-16>>

            reference =
              CallEngine.TestTextToSpeechTransport.deliver_audio_with_result(transport, pcm)

            loop(
              %{
                state
                | streams: Map.put(state.streams, transport, %{stream | left: stream.left - 1}),
                  tts_pending: Map.put(state.tts_pending, reference, {transport, id, stream.left})
              },
              deadline
            )

          _ ->
            loop(state, deadline)
        end

      {:live_browser_finished, evidence} ->
        loop(%{state | browser: evidence}, deadline)

      {:live_scribe_profile, missing, acknowledged} ->
        IO.puts(
          "LIVE_DIAGNOSTICS_ACK " <> JSON.encode!(%{missing: missing, acknowledged: acknowledged})
        )

        loop(
          %{state | provider_profile: %{missing: missing, acknowledged: acknowledged}},
          deadline
        )

      {:live_scribe_pcm, bytes} ->
        loop(%{state | pcm_bytes: state.pcm_bytes + bytes}, deadline)

      {:live_scribe_event, kind, empty?, blank?} ->
        IO.puts(
          "LIVE_DIAGNOSTICS_SCRIBE " <>
            JSON.encode!(%{kind: kind, empty: empty?, blank: blank?, pcm_bytes: state.pcm_bytes})
        )

        loop(state, deadline)

      {:test_tts_audio_result, reference, :ok} ->
        {{transport, id, _left}, pending} = Map.pop!(state.tts_pending, reference)
        Process.send_after(self(), {:tone, transport, id}, 20)
        loop(%{state | tts_pending: pending}, deadline)

      {:test_tts_audio_result, reference, {:error, reason}} ->
        {_transport, _id, left} = Map.fetch!(state.tts_pending, reference)
        flunk("Fixture audio rejected: #{inspect(reason)}; frames remaining: #{left}")

      {:live_browser_failed, error} ->
        if state.call do
          {:ok, facts} =
            Vxpipe.Persistence.ArchiveStore.fetch_call_facts(
              Repo,
              state.call.tenant_key,
              state.call.id
            )

          IO.puts(
            "LIVE_DIAGNOSTICS_ARCHIVE_FAILURE " <>
              JSON.encode!(Enum.frequencies_by(facts, & &1.kind))
          )
        end

        IO.puts("LIVE_DIAGNOSTICS_PCM_FAILURE " <> Integer.to_string(state.pcm_bytes))
        flunk(error)

      _fixture_event ->
        loop(state, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("Live browser diagnostics deadline exceeded")
    end
  end

  defp end_call(call) do
    case CallEngine.RoomAuthority.snapshot(call.tenant_key, call.room_id) do
      %{incarnation_id: incarnation} ->
        CallEngine.end_call(call.tenant_key, call.room_id, incarnation)

      _ ->
        :ok
    end
  catch
    :exit, {:noproc, _} -> :ok
  end

  defp control(transport, payload),
    do: CallEngine.TestTextToSpeechTransport.deliver_control(transport, JSON.encode!(payload))

  defp finished(progress, phase),
    do:
      Agent.update(
        progress,
        &Map.update!(&1, "finished", fn phases -> Enum.uniq([phase | phases]) end)
      )

  defp inspect_report!(state, operational?, key) do
    %{call: call, browser: browser, phase_turns: phases} = state

    assert Enum.sort(Map.keys(phases)) ==
             Enum.sort(["normal", "pause", "barge_base", "barge", "tool"])

    assert MapSet.size(MapSet.new(Map.values(phases), & &1.correlation_id)) == 5
    assert state.tool_executed?
    assert {:ok, ended_call} = Calls.fetch_call(call.tenant_key, call.id, state.calls_options)
    assert ended_call.state == :ended
    assert ended_call.hangup_requested_at != nil

    result = LatencyStore.list_runs(Repo, call.tenant_key, call.id, 50, nil)
    ensure_secret_free!(result, key)
    ensure_secret_free!(browser, key)
    assert {:ok, %{entries: entries}} = result

    assert [entry] = entries
    run = entry.run
    assert run.closed_at != nil
    expected = if operational?, do: "operational_reuse", else: "benchmark_only"

    assert run.profile.inference_source == expected or
             to_string(run.profile.inference_source) == expected

    result = LatencyStore.list_turns(Repo, call.tenant_key, call.id, run.id, 50, nil)
    ensure_secret_free!(result, key)
    assert {:ok, rows} = result
    assert to_string(run.profile.provider) == "elevenlabs"
    assert run.profile.model == "scribe_v2_realtime"
    assert run.profile.commit_strategy == :vad
    assert state.provider_profile != nil

    assert Enum.sort(Enum.map(Map.keys(run.profile.provider_acknowledgement), &to_string/1)) ==
             Enum.sort(state.provider_profile.acknowledged)

    [api_run] = browser["stored"]["report"]["runs"]
    assert api_run["profile"] == run.profile |> JSON.encode!() |> JSON.decode!()
    assert api_run["profile"]["commit_strategy"] == "vad"

    for missing <- state.provider_profile.missing do
      refute Map.has_key?(api_run["profile"]["provider_acknowledgement"], missing)
    end

    IO.puts("LIVE_DIAGNOSTICS_PROFILE scribe_v2_realtime/vad/" <> expected)
    assert Enum.all?(rows, &(is_binary(&1.provider_turn_id) and &1.provider_turn_id != ""))
    api_rows = browser["stored"]["turns"]["turns"]
    assert MapSet.new(api_rows, & &1["turn_id"]) == MapSet.new(rows, & &1.turn_id)

    for row <- rows do
      api = Enum.find(api_rows, &(&1["turn_id"] == row.turn_id))
      assert api["clock_id"] == row.clock_id
      assert api["source_epoch"] == row.source_epoch
      assert api["provider_turn_id"] == row.provider_turn_id

      assert api["durations_us"] ==
               Map.new(row.durations_us, fn {key, value} -> {to_string(key), value} end)

      assert api["barge_in"] ==
               if(row.barge_in, do: row.barge_in |> JSON.encode!() |> JSON.decode!(), else: nil)
    end

    endpoints = Enum.filter(rows, &is_integer(&1.durations_us[:speech_end_to_provider_end]))

    barges =
      for row <- rows,
          row.barge_in != nil,
          entry <- row.barge_in.entries,
          is_integer(entry.duration_us),
          do: entry

    IO.puts(
      "LIVE_DIAGNOSTICS_METRICS " <>
        JSON.encode!(%{
          endpoint_us: Enum.map(rows, & &1.durations_us[:speech_end_to_provider_end]),
          barge_us: Enum.map(barges, & &1.duration_us),
          acoustic_reasons: Enum.map(rows, & &1.acoustic_reason),
          canonical_turn_count: length(rows),
          endpoint_measurement_count: length(endpoints),
          barge_measurement_count: length(barges)
        })
    )

    assert endpoints != []
    pause_turn = Enum.find(rows, &(&1.turn_id == phases["pause"].correlation_id))
    assert pause_turn != nil

    if pause_turn.durations_us.speech_end_to_provider_end == nil do
      assert pause_turn.metric_reasons.speech_end_to_provider_end != nil
    end

    assert length(barges) >= 1
    assert Enum.all?(barges, &(&1.duration_us == &1.playback_stopped_us - &1.speech_started_us))

    for {_phase, identity} <- phases do
      assert identity.source_participant_id == run.participant_id
      assert identity.connection_id == run.connection_id

      assert Enum.any?(
               rows,
               &(&1.turn_id == identity.correlation_id and &1.clock_id == run.clock_id)
             )
    end

    tool = Enum.find(rows, &(&1.turn_id == phases["tool"].correlation_id))
    assert tool.response_turn_id == nil
    refute Map.has_key?(tool.landmarks_us, :first_audio_started)
    assert tool.durations_us.speech_end_to_first_audio == nil
    assert tool.metric_reasons.speech_end_to_first_audio != nil
    interrupted = Enum.find(rows, &(&1.turn_id == phases["barge"].correlation_id))
    assert interrupted.barge_in != nil
    base = phases["barge_base"]

    assert Enum.any?(interrupted.barge_in.entries, fn entry ->
             entry.response_turn_id == base.correlation_id and
               entry.response_command_id == base.command_id and
               entry.response_source_participant_id == base.source_participant_id and
               entry.output_connection_id == base.connection_id and is_integer(entry.duration_us)
           end)

    for row <- endpoints do
      assert row.durations_us.speech_end_to_provider_end ==
               row.landmarks_us.provider_end_received - row.landmarks_us.acoustic_end
    end

    evidence = %{
      scribe_provider: "elevenlabs",
      inference_source: expected,
      canonical_turns: length(rows),
      endpoint_measurements: length(endpoints),
      pause_resume: browser["pause_resume"],
      barge_in_count: length(barges),
      tool_only: state.tool_executed? and tool.response_turn_id == nil,
      hung_up: browser["hung_up"],
      persisted_after_hangup: true
    }

    Map.put(evidence, :secret_free, true)
  end

  defp ensure_secret_free!(value, key) do
    if String.contains?(inspect(value, limit: :infinity, printable_limit: :infinity), key),
      do: flunk("Provider credential appeared in diagnostic evidence")

    :ok
  end

  defp source(vad) do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{
        capabilities: %{
          speech_to_text: %{
            provider: "elevenlabs",
            model: "scribe_v2_realtime",
            credential_name: "scribe",
            vad: vad
          }
        }
      },
      media_policy: %{record_audio: true, save_transcripts: true},
      wait_sounds: %{call_setup: nil},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Fixture reply",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{
            model_inference: %{provider: "fixture", model: "echo"},
            text_to_speech: %{
              provider: "deepgram",
              model: "flux-test-voice",
              credential_name: "fixture-tts",
              options: %{encoding: "linear16", sample_rate: 48_000}
            }
          },
          tools: %{"wait_for_test" => %{type: "host", tool: "wait_for_test"}}
        }
      },
      limits: %{max_duration_ms: 240_000}
    }
  end

  defp identity! do
    dependencies = %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      installations: Vxpipe.Persistence.IdentityInstallationStore,
      diagnostics_settings: DiagnosticsSettingsStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      audit: Vxpipe.Persistence.IdentityAuditStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }

    for {app, key, value} <- [
          {:vxpipe_identity, :dependencies, dependencies},
          {:vxpipe_console, :user_identity_backend, nil}
        ] do
      previous = Application.get_env(app, key)
      restore(app, key, value)
      on_exit(fn -> restore(app, key, previous) end)
    end

    proof =
      case Vxpipe.Identity.Bootstrap.status(dependencies) do
        {:ok, :pending_first_run} ->
          nil

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} =
            Vxpipe.Persistence.IdentityInstallationStore.issue_setup_proof(900)

          proof
      end

    assert build_conn()
           |> post("http://localhost/auth/api/setup", %{
             "email" => @email,
             "password" => @password,
             "password_confirmation" => @password,
             "public_url" => "http://localhost:4000",
             "proof" => proof
           })
           |> json_response(200) == %{"ok" => true}

    role = Repo.get_by!(IdentityRole, kind: "admin")
    user = Repo.get_by!(IdentityUser, normalized_email: @email)
    Repo.update!(Ecto.Changeset.change(user, role_id: role.id))
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

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  defp build_site! do
    directory =
      Path.join(
        System.tmp_dir!(),
        "vxpipe-live-diagnostics-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script =
      "require('esbuild').buildSync({stdin:{contents:'import React from \"react\";import{createRoot}from\"react-dom/client\";import PlaygroundApp from\"./src/PlaygroundApp\";import\"@pipecat-ai/voice-ui-kit/styles\";import\"./src/styles.css\";createRoot(document.getElementById(\"root\")).render(<PlaygroundApp/>);',resolveDir:process.cwd(),loader:'tsx'},bundle:true,jsx:'automatic',outdir:process.argv[1],entryNames:'site',loader:{'.woff2':'file','.woff':'file'},publicPath:'/__structured'});"

    {output, status} =
      System.cmd("node", ["-e", script, directory],
        cd: Path.expand("../../assets", __DIR__),
        stderr_to_stdout: true
      )

    assert status == 0, output
    directory
  end
end
