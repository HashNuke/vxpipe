defmodule Vxpipe.Console.Integration.StructuredAgentBrowserTest do
  use ExUnit.Case, async: false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Console.Endpoint

  alias Vxpipe.Console.Test.{
    StructuredBrowserDriver,
    StructuredBrowserSite,
    StructuredBrowserTTSWire
  }

  alias Vxpipe.Gateway.{CallAdmission, HTTP.Mount}

  alias Vxpipe.Persistence.{
    AccessKeyStore,
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Providers.{Deepgram.TTSSession, LiveModels}

  @moduletag :live_providers
  @moduletag timeout: 600_000

  for {provider, tag} <- [{"openai", :live_openai}, {"google", :live_gemini}] do
    @tag tag
    @tag :live_universal_browser
    test "published #{provider} dialogue reaches Chrome through native tools and real TTS" do
      provider = unquote(provider)
      if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)

      sandbox =
        Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 600_000)

      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)

      {:ok, keyring} =
        CredentialKeyring.new("browser", %{"browser" => :crypto.strong_rand_bytes(32)})

      original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)
      original_mount = Endpoint.config(:gateway_mount)
      original_observer = Application.fetch_env(:vxpipe_console, :structured_browser_observer)
      original_tool_observer = Application.fetch_env(:vxpipe_call_engine, :blocking_tool_observer)
      original_telemetry = Application.fetch_env(:req_llm, :telemetry)
      Application.put_env(:req_llm, :telemetry, payloads: :raw)
      Application.put_env(:vxpipe_console, :structured_browser_observer, self())
      Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())

      Application.put_env(
        :vxpipe_call_engine,
        CallEngine.Application,
        original
        |> Keyword.update!(:agent_runtime, &Keyword.put(&1, :tool_invocation_timeout_ms, 120_000))
        |> Keyword.update!(:call_lifecycle, &Keyword.put(&1, :idle_timeout_ms, 600_000))
      )

      on_exit(fn ->
        Application.put_env(:vxpipe_call_engine, CallEngine.Application, original)
        Phoenix.Config.put(Endpoint, :gateway_mount, original_mount)
        restore_env(:vxpipe_console, :structured_browser_observer, original_observer)
        restore_env(:vxpipe_call_engine, :blocking_tool_observer, original_tool_observer)
        restore_env(:req_llm, :telemetry, original_telemetry)
      end)

      options = [
        access_key_repository: {AccessKeyStore, Repo},
        credential_repository: {CredentialStore, Repo},
        call_spec_repository: {CallSpecStore, Repo},
        call_repository: {CallStore, Repo},
        provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
        speech_runtime: [
          text_to_speech: [
            providers: %{
              TTSSession => [wire_module: StructuredBrowserTTSWire, maximum_requests: 16]
            }
          ]
        ],
        registries: %{host_tools: %{"wait_for_test" => CallEngine.TestBlockingTool}},
        publication_enabled: false
      ]

      options = Keyword.put(options, :credential_source, {ProviderCredentialSource, options})

      {:ok, tenant, issued} =
        Administration.bootstrap_tenant(
          "Structured browser acceptance",
          [:admin, :calls],
          options
        )

      {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)

      for {provider, name, env} <- [
            {provider, "llm", LiveModels.llm(provider).env},
            {"deepgram", "speech", "DEEPGRAM_API_KEY"}
          ] do
        assert {:ok, _} =
                 ProviderCredentials.provision(
                   tenant.key,
                   provider,
                   name,
                   "api_key",
                   %{"api_key" => System.fetch_env!(env)},
                   options
                 )
      end

      assert {:ok, revision} = Calls.save_call_spec(tenant.key, source(provider), options)
      assert revision.validation_errors == []
      assert revision.compiled_metadata["agent_protocol"]["version"] == "mode_message_v1"

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
        Mount.init(call_admission: [enabled: true, backend: {CallAdmission, options}])
      )

      assets = build_site!()

      server =
        start_supervised!(
          {Bandit,
           plug:
             {StructuredBrowserSite,
              %{
                owner: self(),
                assets: assets,
                principal: principal,
                route: route.key,
                calls: options
              }},
           ip: {127, 0, 0, 1},
           port: 0}
        )

      {:ok, {_address, port}} = ThousandIsland.listener_info(server)
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach_many(
          handler,
          [[:finch, :request, :start], [:req_llm, :request, :stop]],
          &__MODULE__.capture_request/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)
      url = "http://127.0.0.1:#{port}/admin/samples/pipecat-console"
      IO.puts("structured_browser_ready " <> url)
      owner = self()

      start_supervised!(
        {Task,
         fn ->
           try do
             evidence = StructuredBrowserDriver.run(url)

             send(
               owner,
               {:structured_browser_control, %{"action" => "finish", "evidence" => evidence}}
             )
           rescue
             error -> send(owner, {:structured_browser_failed, Exception.message(error)})
           end
         end}
      )

      collect(
        %{provider: provider, calls: [], requests: [], responses: [], speech: [], tool: nil},
        System.monotonic_time(:millisecond) + 540_000
      )
    end
  end

  def capture_request(
        _event,
        _measurements,
        %{request: %{host: host, body: body}},
        owner
      )
      when host in ["api.openai.com", "generativelanguage.googleapis.com"] do
    case body |> IO.iodata_to_binary() |> JSON.decode() do
      {:ok, request} -> send(owner, {:structured_browser_request, request})
      _ -> :ok
    end
  end

  def capture_request(
        [:req_llm, :request, :stop],
        measurements,
        %{provider: provider} = metadata,
        owner
      )
      when provider in [:openai, :google] do
    message = get_in(metadata, [:response_payload, :message]) || %{}

    response = %{
      duration_ms: System.convert_time_unit(measurements.duration, :native, :microsecond) / 1_000,
      finish_reason: metadata.finish_reason,
      usage: metadata.usage,
      content:
        message
        |> Map.get(:content, [])
        |> Enum.filter(&(Map.get(&1, :type) == :text))
        |> Enum.map(&Map.take(&1, [:type, :text])),
      tool_call_count: message |> Map.get(:tool_calls) |> List.wrap() |> length()
    }

    send(owner, {:structured_browser_response, response})
  end

  def capture_request(_event, _measurements, _metadata, _owner), do: :ok

  defp collect(state, deadline) do
    receive do
      {:structured_browser_call, call} ->
        on_exit(fn -> end_call(call) end)

        collect(%{state | calls: [call | state.calls]}, deadline)

      {:structured_browser_request, request} ->
        IO.puts(
          "structured_browser_request " <>
            JSON.encode!(%{
              number: length(state.requests) + 1,
              format: get_in(request, ["text", "format", "type"]),
              input_items: length(wire_items(request))
            })
        )

        collect(%{state | requests: state.requests ++ [request]}, deadline)

      {:structured_browser_tts, %{"type" => "Speak", "text" => text}} ->
        collect(%{state | speech: state.speech ++ [text]}, deadline)

      {:structured_browser_response, response} ->
        IO.puts("structured_browser_response " <> JSON.encode!(response))
        collect(%{state | responses: state.responses ++ [response]}, deadline)

      {:test_blocking_tool_started, tool} ->
        collect(%{state | tool: tool}, deadline)

      {:structured_browser_control, %{"action" => "release_tool"}} ->
        assert is_pid(state.tool)
        send(state.tool, :release_test_tool)
        collect(state, deadline)

      {:structured_browser_control, %{"action" => "status"}} ->
        IO.puts(
          "structured_browser_status " <>
            JSON.encode!(%{
              speech: state.speech,
              requests: length(state.requests),
              tool_started: is_pid(state.tool)
            })
        )

        collect(state, deadline)

      {:structured_browser_control, %{"action" => "finish", "evidence" => evidence}} ->
        IO.puts(
          "structured_browser_evidence " <>
            JSON.encode!(%{
              provider: state.provider,
              speech: state.speech,
              requests: length(state.requests),
              browser: evidence
            })
        )

        assert state.calls != []
        assert length(state.requests) >= 8

        for expected <- ["Ready", "Checking", "Four", "Lookup complete"] do
          assert Enum.any?(state.speech, &String.contains?(&1, expected))
        end

        Vxpipe.Console.Test.UniversalBrowserAssertions.assert_transcript(evidence, state.speech)
        refute JSON.encode!(state.requests) =~ "pending_tool_invocations"
        assert evidence["audioPackets"] > 0
        assert evidence["speechFrames"] > 0
        assert evidence["toolsStarted"] == 3
        assert evidence["toolsCompleted"] == 3

        assert Enum.map(evidence["cases"], & &1["text"]) ==
                 [
                   "SHORT",
                   "LONG",
                   "QUIET",
                   "LOOKUP",
                   "MATH",
                   "TOOL_COMPLETION",
                   "SHORT",
                   "IDLE_SPOKEN",
                   "IDLE_SPOKEN_TIMEOUT",
                   "IDLE_SILENT",
                   "IDLE_SILENT_TIMEOUT"
                 ]

        for observed <- evidence["cases"] do
          assert observed["completed"]
          refute observed["error"]

          if observed["text"] in ["QUIET", "IDLE_SILENT"] do
            assert observed["audioFrames"] == 0
            assert observed["output"] == []
            assert observed["firstAudioMs"] == nil
          else
            assert observed["audioFrames"] > 0
            assert observed["firstAudioMs"] > 0
            assert observed["output"] != []
          end
        end

        idle_completions =
          Enum.filter(evidence["timeline"], fn event ->
            event["type"] == "llm-function-call-stopped" and
              event["data"]["function_name"] == "idle"
          end)

        assert length(idle_completions) == 2

        for {label, completion} <- Enum.zip(["IDLE_SPOKEN", "IDLE_SILENT"], idle_completions) do
          acknowledgment = Enum.find(evidence["cases"], &(&1["text"] == label))
          timeout = Enum.find(evidence["cases"], &(&1["text"] == label <> "_TIMEOUT"))
          assert completion["data"]["result"] == %{"status" => "expired"}
          assert completion["at"] - acknowledgment["completedAt"] >= 9_800
          assert timeout["outputAt"] >= completion["at"]
        end

        assert Enum.count(state.requests, fn request ->
                 last = List.last(wire_items(request))
                 last && JSON.encode!(last) =~ "idle_timeout"
               end) == 2

        assert_wire_contract(state.provider, state.requests)

      {:structured_browser_admission_failed, reason} ->
        flunk("browser admission failed: #{inspect(reason)}")

      {:structured_browser_failed, reason} ->
        flunk(reason)

      _observation ->
        collect(state, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("structured browser acceptance did not finish")
    end
  end

  defp wire_items(%{"input" => input}), do: input
  defp wire_items(%{"contents" => contents}), do: contents

  defp assert_wire_contract("google", requests) do
    for request <- requests do
      Vxpipe.Console.Test.UniversalBrowserAssertions.assert_google_tool_mode(request)
      declarations = Enum.flat_map(request["tools"], &Map.get(&1, "functionDeclarations", []))
      assert Enum.sort(Enum.map(declarations, & &1["name"])) == ["idle", "wait_for_test"]
      assert JSON.encode!(request["systemInstruction"]) =~ "agent_mode"
      refute JSON.encode!(request["tools"]) =~ "structured_output"
    end

    wire = JSON.encode!(List.last(requests))
    assert wire =~ "functionCall"
    assert wire =~ "functionResponse"
    assert wire =~ "tool_invocation_completion"
  end

  defp assert_wire_contract("openai", requests) do
    wire = JSON.encode!(List.last(requests))
    assert wire =~ "function_call"
    assert wire =~ "function_call_output"
    assert wire =~ "tool_invocation_completion"

    for [previous, current] <- Enum.chunk_every(requests, 2, 1, :discard) do
      assert Map.delete(previous, "input") == Map.delete(current, "input")
      assert Enum.take(current["input"], length(previous["input"])) == previous["input"]
    end

    for request <- requests do
      assert get_in(request, ["text", "format", "strict"]) == true

      assert get_in(request, ["text", "format", "schema"]) ==
               Vxpipe.AgentRuntime.Dialogue.schema()

      assert Enum.sort(Enum.map(request["tools"], & &1["name"])) == ["idle", "wait_for_test"]
    end
  end

  defp end_call(call) do
    case CallEngine.RoomAuthority.snapshot(call.tenant_key, call.room_id) do
      %{incarnation_id: incarnation} ->
        CallEngine.end_call(call.tenant_key, call.room_id, incarnation)

      _ended ->
        :ok
    end
  catch
    :exit, {:noproc, _call} -> :ok
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)

  defp build_site! do
    directory =
      Path.join(
        System.tmp_dir!(),
        "vxpipe-structured-browser-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    assets = Path.expand("../../assets", __DIR__)

    script = """
    require('esbuild').buildSync({stdin:{contents:'import React from "react"; import {createRoot} from "react-dom/client"; import PlaygroundApp from "./src/PlaygroundApp"; import "@pipecat-ai/voice-ui-kit/styles"; import "./src/styles.css"; createRoot(document.getElementById("root")).render(<PlaygroundApp/>);',resolveDir:process.cwd(),loader:'tsx'},bundle:true,jsx:'automatic',outdir:process.argv[1],entryNames:'site',assetNames:'[name]-[hash]',loader:{'.woff2':'file','.woff':'file'},publicPath:'/__structured'});
    """

    {output, status} =
      System.cmd("node", ["-e", script, directory], cd: assets, stderr_to_stdout: true)

    assert status == 0, output
    directory
  end

  defp source(provider) do
    %{
      schema_version: "20260915.01",
      name: "Structured browser acceptance",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      tool_visibility: "full",
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt:
            "This is an acceptance call. Interpret the participant's exact command. Every spoken reply is a main response with agent_mode speaker, including tool acknowledgment. SHORT: say Ready. LONG: give a single sentence of about sixty words about a garden. QUIET: return listener with null and say nothing. LOOKUP: call wait_for_test exactly once. When its native result says status running, immediately return speaker with message Checking; do not wait for completion and do not return listener/null for this acknowledgment. MATH: say Four without calling tools. When the lookup's real completion arrives, say Lookup complete. Do not repeat a running tool. IDLE_SPOKEN: call idle exactly once with duration_seconds 10, then say Okay, I will wait. IDLE_SILENT: call idle exactly once with duration_seconds 10, then return listener with null. On idle_timeout say Ready again without calling any tool.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{
            model_inference: %{
              provider: provider,
              model: LiveModels.llm(provider).model,
              credential_name: "llm",
              options: %{max_tokens: 4096}
            },
            text_to_speech: %{
              provider: "deepgram",
              model: LiveModels.speech("deepgram", :tts),
              credential_name: "speech",
              options: %{encoding: "linear16", sample_rate: 48_000}
            }
          },
          tools: %{
            "idle" => %{type: "platform", tool: "idle"},
            "wait_for_test" => %{
              type: "host",
              tool: "wait_for_test",
              conversation_mode: "non_blocking"
            }
          },
          transfers: []
        }
      },
      limits: %{max_duration_ms: 600_000}
    }
  end
end
