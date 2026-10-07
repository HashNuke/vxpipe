defmodule Vxpipe.CallEngine.PlanStartup.OutputSTTConfigurationTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.CallEngine.{
    CapabilityCatalog,
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    PlanStartup
  }

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.TestTenantCredentialSource
  alias Vxpipe.Providers.Google.{STT, STTSession}
  alias Vxpipe.Providers.MorseCode.STSSession

  test "hosted STT without finite-input proof is rejected before credentials or allocation" do
    for recognizer <- [
          google(),
          %{
            provider: "deepgram",
            model: "flux-general-en",
            options: %{encoding: "linear16", sample_rate: 16_000}
          }
        ] do
      plan = plan(16_000, recognizer)

      for result <- [PlanStartup.validate(plan, options()), PlanStartup.new(plan, options())] do
        assert {:error, error} = result

        assert error.details["path"] == [
                 "participants",
                 "assistant",
                 "capabilities",
                 "output_speech_to_text"
               ]

        assert error.details["reason"] =~ "finite-input"
      end
    end

    refute_received {:tenant_credential_resolved, _, _, _}
    refute_received {:test_google_stt_started, _, _}
  end

  test "direct sidecar allocation also rejects a non-finite descriptor before startup" do
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output

    for provider <- [STTSession, Vxpipe.Providers.Deepgram.STTSession] do
      state = %{output_stt: nil, output_stt_options: {{provider, []}, self(), []}}
      assert {:error, :unsupported_finite_input} = Output.start_output_stt(state)
    end

    refute_received {:test_google_stt_started, _, _}
  end

  test "ordinary human Google STT retains private configuration and actual fake-wire startup" do
    alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}

    assert {:ok, startup} =
             PlanStartup.new(plan(16_000, morse(), %{speech_to_text: google()}), options())

    runtime = startup.speech_to_text_runtimes[startup.caller.participant_id]
    assert {STTSession, public} = runtime.provider
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: public,
               private: runtime.provider_private,
               owner: self()
             )

    assert_receive {:test_google_stt_started, wire, connection}, 1_000
    assert connection.headers == [{"x-goog-api-key", "synthetic-output-stt-private"}]
    assert_receive {:test_google_stt_control, ^wire, payload}, 1_000
    assert JSON.decode!(payload)["setup"]["model"] == "models/gemini-3.5-transcribe-live"
    refute payload =~ "synthetic-output-stt-private"
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    recognizer = Session.provider(session)
    assert :sys.get_state(recognizer).config.api_key == "synthetic-output-stt-private"

    refute inspect(:sys.get_status(recognizer)) =~ "synthetic-output-stt-private"
    refute inspect(startup) =~ "synthetic-output-stt-private"
    refute inspect(runtime) =~ "synthetic-output-stt-private"

    refute_received {:test_google_stt_audio, _, _}
    monitor = Process.monitor(recognizer)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}, 1_000
  end

  test "Google output recognition resolves the same existing STT adapter and options" do
    assert {:ok, input} = CapabilitySelection.new(google(), :speech_to_text, [])
    output = %{input | kind: :output_speech_to_text}
    assert {:ok, STTSession} = CapabilityCatalog.adapter(output)
    assert CapabilityCatalog.speech_options(output) == CapabilityCatalog.speech_options(input)
    assert :ok = CapabilitySelection.validate(output, [])
    settings = Keyword.fetch!(options(), :speech_to_text)

    assert CapabilityCatalog.provider_settings(settings, STTSession, :output_speech_to_text) ==
             CapabilityCatalog.provider_settings(settings, STTSession, :speech_to_text)
  end

  test "startup keeps human credentials independent of the finite sidecar and STS generator" do
    plan = plan(16_000, morse(), %{speech_to_text: google()})
    assert {:ok, startup} = PlanStartup.new(plan, options())
    runtime = startup.speech_to_speech
    human = startup.speech_to_text_runtimes[startup.caller.participant_id]
    assert {STTSession, public} = human.provider
    private = human.provider_private
    assert {Vxpipe.Providers.MorseCode.STTSession, _} = runtime.output_speech_to_text
    assert runtime.output_speech_to_text_private == []
    assert %STT{api_key: "synthetic-output-stt-private", sample_rate: 16_000} = private[:config]
    assert private[:wire_module] == Vxpipe.CallEngine.TestGoogleSTTTransport
    assert private[:wire_options] == [observer: self(), ready_on_start: true]
    assert public[:model] == "gemini-3.5-transcribe-live"
    refute Keyword.has_key?(public, :api_key)

    assert Keyword.fetch!(runtime.provider_private, :activation).system_prompt ==
             "Reply privately."

    refute inspect(startup) =~ "synthetic-output-stt-private"
    refute inspect(runtime) =~ "synthetic-output-stt-private"
    assert_received {:tenant_credential_resolved, "tenant-output-config", "google", "recognizer"}
  end

  test "human Google recognition retains host and tenant credential admission gates" do
    plan = plan(16_000, morse(), %{speech_to_text: google()})

    for registry <- [%{}, %{STTSession => [enabled: false]}] do
      settings = Keyword.put(options(), :speech_to_text, providers: registry)
      assert {:error, error} = PlanStartup.validate(plan, settings)

      assert error.details["path"] ==
               ["participants", "caller", "capabilities", "speech_to_text"]
    end

    for credentials <- [
          %{},
          %{{"other-tenant", "google", "recognizer"} => %{"api_key" => "wrong-tenant"}}
        ] do
      settings =
        Keyword.put(
          options(),
          :credential_source,
          {TestTenantCredentialSource, {self(), credentials}}
        )

      assert {:error, _error} = PlanStartup.new(plan, settings)
      refute_received {:test_google_stt_started, _, _}
    end
  end

  test "a finite sidecar still requires its existing STT host enablement" do
    plan = plan(16_000, morse())

    for registry <- [%{}, %{Vxpipe.Providers.MorseCode.STTSession => [enabled: false]}] do
      settings = Keyword.put(options(), :speech_to_text, providers: registry)

      assert {:error, error} = PlanStartup.validate(plan, settings)

      assert error.details["path"] == [
               "participants",
               "assistant",
               "capabilities",
               "output_speech_to_text"
             ]

      # Construction retains its existing enclosing STS-runtime error projection.
      assert {:error, error} = PlanStartup.new(plan, settings)

      assert error.details["path"] == [
               "participants",
               "assistant",
               "capabilities",
               "speech_to_speech"
             ]
    end
  end

  test "mismatched output PCM fails admission before credential lookup or wire startup" do
    for recognizer <- [
          google(),
          %{provider: "morse", model: "morse", options: %{sample_rate: 16_000}}
        ] do
      plan = plan(24_000, recognizer)

      for result <- [PlanStartup.validate(plan, options()), PlanStartup.new(plan, options())] do
        assert {:error, error} = result
        assert error.code == :unsupported_call_plan

        assert error.details["path"] ==
                 ["participants", "assistant", "capabilities", "output_speech_to_text"]

        refute inspect(error) =~ "synthetic-output-stt-private"
        refute inspect(error) =~ "Reply privately."
      end

      assert {:error, error} =
               Vxpipe.CallEngine.start_call(plan, Keyword.take(options(), [:credential_source]))

      assert error.details["path"] ==
               ["participants", "assistant", "capabilities", "output_speech_to_text"]

      assert Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) == []
      refute_received {:tenant_credential_resolved, _, _, _}
      refute_received {:test_google_stt_started, _, _}
    end
  end

  test "independent human STT format does not constrain compatible agent output" do
    human = %{
      speech_to_text: %{provider: "morse", model: "morse", options: %{sample_rate: 8_000}}
    }

    assert {:ok, startup} = PlanStartup.new(plan(16_000, morse(), human), options())

    assert {Vxpipe.Providers.MorseCode.STTSession, human_options} =
             startup.speech_to_text_runtimes[startup.caller.participant_id].provider

    assert human_options[:sample_rate] == 8_000

    assert {Vxpipe.Providers.MorseCode.STTSession, recognizer_options} =
             startup.speech_to_speech.output_speech_to_text

    assert recognizer_options[:sample_rate] == 16_000

    assert startup.speech_to_speech.output_speech_to_text_private == []
  end

  test "output slot rejects invalid public selections independently of Google STS" do
    for selection <- [
          %{google() | provider: "unknown"},
          %{google() | model: "unsupported"},
          %{google() | options: %{sample_rate: 8_000}},
          %{google() | options: %{api_key: "public-key"}},
          %{google() | options: %{wire_module: "injected"}}
        ] do
      assert {:error, _} = CapabilitySelection.new(selection, :output_speech_to_text, [])
    end

    assert {:ok, Vxpipe.Providers.Google.STSSession} =
             Vxpipe.Providers.Registry.fetch_capability("google", :sts)
  end

  defp google do
    %{
      provider: "google",
      model: "gemini-3.5-transcribe-live",
      credential_name: "recognizer",
      options: %{sample_rate: 16_000}
    }
  end

  defp morse, do: %{provider: "morse", model: "morse", options: %{sample_rate: 16_000}}

  defp plan(rate, recognizer, human_capabilities \\ %{}) do
    source = %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: %{call_setup: nil},
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: human_capabilities
        },
        "assistant" => %{
          type: "agent",
          prompt: "Reply privately.",
          tools: %{},
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{
            speech_to_speech: %{
              provider: "morse",
              model: "morse",
              options: %{sample_rate: rate, output_transcript: false}
            },
            output_speech_to_text: recognizer
          }
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "output-config", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "output-config", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-output-config",
               actor_id: "actor-output-config"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end

  defp options do
    [
      credential_source:
        {TestTenantCredentialSource,
         {self(),
          %{
            {"tenant-output-config", "google", "recognizer"} => %{
              "api_key" => "synthetic-output-stt-private"
            }
          }}},
      speech_to_speech: [providers: %{STSSession => [enabled: true]}],
      text_to_speech: [providers: %{}],
      speech_to_text: [
        providers: %{
          Vxpipe.Providers.MorseCode.STTSession => [enabled: true, media_ingress: []],
          STTSession => [
            enabled: true,
            media_ingress: [],
            wire_module: Vxpipe.CallEngine.TestGoogleSTTTransport,
            wire_options: [observer: self(), ready_on_start: true]
          ]
        }
      ]
    ]
  end
end
