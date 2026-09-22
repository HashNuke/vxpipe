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

  test "room allocation hands selected Google STT private config to the sidecar fake wire" do
    alias Vxpipe.CallEngine

    alias Vxpipe.CallEngine.{
      RoomCapabilitySupervisor,
      TestAudioOutputSink,
      TestCallStartup,
      TestTransferConnection
    }

    alias Vxpipe.CallEngine.Command.AttachConnection
    alias Vxpipe.CallEngine.Speech.Session

    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      Keyword.merge(original, Keyword.take(options(), [:speech_to_text, :speech_to_speech]))

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)

    plan = plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    assert {:ok, room} =
             TestCallStartup.start_call(plan, Keyword.take(options(), [:credential_source]))

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "output-source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} =
             TestTransferConnection.attach(command, sink,
               input_track: %{
                 track_id: "microphone",
                 codec: :linear16,
                 sample_rate: 16_000,
                 channels: 1
               }
             )

    assert_receive {:test_google_stt_started, wire, connection}, 1_000
    assert connection.headers == [{"x-goog-api-key", "synthetic-output-stt-private"}]
    assert_receive {:test_google_stt_control, ^wire, payload}, 1_000
    assert JSON.decode!(payload)["setup"]["model"] == "models/gemini-3.5-transcribe-live"
    refute payload =~ "synthetic-output-stt-private"
    TestCallStartup.await_ready(plan.room_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    state = :sys.get_state(capability)
    assert {STTSession, _public} = state.output_stt.provider
    recognizer = Session.provider(state.output_stt.session)
    assert :sys.get_state(recognizer).config.api_key == "synthetic-output-stt-private"

    for pid <- [capability, recognizer] do
      refute inspect(:sys.get_status(pid)) =~ "synthetic-output-stt-private"
      refute inspect(:sys.get_status(pid)) =~ "Reply privately."
    end

    refute_received {:test_google_stt_audio, _, _}
    monitor = Process.monitor(recognizer)
    stop_supervised!({TestTransferConnection, command.connection_id})
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

  test "startup retains recognizer private configuration separately from the STS generator" do
    plan = plan()
    assert {:ok, startup} = PlanStartup.new(plan, options())
    runtime = startup.speech_to_speech
    assert {STTSession, public} = runtime.output_speech_to_text
    private = runtime.output_speech_to_text_private
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

  test "output recognition retains host and tenant credential admission gates" do
    plan = plan()

    for registry <- [%{}, %{STTSession => [enabled: false]}] do
      settings = Keyword.put(options(), :speech_to_text, providers: registry)
      assert {:error, error} = PlanStartup.validate(plan, settings)

      assert error.details["path"] ==
               ["participants", "assistant", "capabilities", "output_speech_to_text"]
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

  test "output slot rejects invalid public selections without enabling Google STS" do
    for selection <- [
          %{google() | provider: "unknown"},
          %{google() | model: "unsupported"},
          %{google() | options: %{sample_rate: 8_000}},
          %{google() | options: %{api_key: "public-key"}},
          %{google() | options: %{wire_module: "injected"}}
        ] do
      assert {:error, _} = CapabilitySelection.new(selection, :output_speech_to_text, [])
    end

    assert {:error, _} = Vxpipe.Providers.Registry.fetch_capability("google", :sts)
  end

  defp google do
    %{
      provider: "google",
      model: "gemini-3.5-transcribe-live",
      credential_name: "recognizer",
      options: %{sample_rate: 16_000}
    }
  end

  defp plan do
    source = %{
      schema_version: CallSpec.schema_version(),
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: %{call_setup: nil},
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
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
              options: %{sample_rate: 16_000, output_transcript: false}
            },
            output_speech_to_text: google()
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
          STTSession => [
            enabled: true,
            wire_module: Vxpipe.CallEngine.TestGoogleSTTTransport,
            wire_options: [observer: self(), ready_on_start: true]
          ]
        }
      ]
    ]
  end
end
