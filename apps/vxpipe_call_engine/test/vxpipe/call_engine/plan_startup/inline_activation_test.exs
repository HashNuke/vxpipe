defmodule Vxpipe.CallEngine.PlanStartup.InlineActivationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler, PlanStartup}
  alias Vxpipe.Providers.Deepgram.TTSSession, as: TTSFluxSession
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.Providers.Rime.TTSSession, as: RimeTTSSession
  alias Vxpipe.Providers.Google.TTSSession, as: GoogleTTSSession
  alias Vxpipe.Providers.Google.STTSession, as: GoogleSTTSession
  alias Vxpipe.Providers.Cartesia.TTSSession, as: CartesiaTTSSession
  alias Vxpipe.Providers.Cartesia.STTSession, as: CartesiaSTTSession
  alias Vxpipe.CallEngine.TestTenantCredentialSource
  alias Vxpipe.CallEngine.ConnectionSpeechPreparation

  test "activates inline model and speech using only the selected tenant credentials" do
    plan = plan()
    assert {:ok, startup} = PlanStartup.new(plan, options())
    model = Keyword.fetch!(startup.agent_activation, :model)
    assert model.api_key == "google-tenant-private-marker"
    assert model.model.provider == :google
    assert model.model.id == "gemini-2.5-flash"
    assert model.generation_options[:temperature] == 0.2

    assert model.generation_options[:base_url] ==
             "https://generativelanguage.googleapis.com/v1beta"

    refute inspect(startup) =~ "private-marker"

    caller = plan.participants["caller"]
    stt = Map.fetch!(startup.speech_to_text_runtimes, caller.participant_id)
    assert {FluxSession, public_stt_config} = stt.provider
    assert public_stt_config[:model] == "flux-general-en"

    assert [
             config: stt_config,
             wire_module: Vxpipe.Providers.Deepgram.STTSocket,
             wire_options: []
           ] = stt.provider_private

    assert stt_config.api_key == "deepgram-tenant-private-marker"
    assert {TTSFluxSession, public_tts_config} = startup.text_to_speech.provider
    assert public_tts_config[:model] == "flux-haley-en"
    assert public_tts_config[:sample_rate] == 48_000

    assert [config: tts_config, wire_module: _, wire_options: []] =
             startup.text_to_speech.provider_private

    assert tts_config.api_key == "deepgram-tenant-private-marker"

    for provider <- ["google", "deepgram"] do
      assert_received {:tenant_credential_resolved, "tenant-inline", ^provider, "default"}
    end

    refute :erlang.term_to_binary(plan) =~ "private-marker"
  end

  test "Rime TTS activation resolves its own credential and exposes only public options" do
    plan =
      plan(%{
        provider: "rime",
        model: "coda",
        options: %{speaker: "astra", sample_rate: 24_000}
      })

    options = options()

    {TestTenantCredentialSource, {observer, bindings}} =
      Keyword.fetch!(options, :credential_source)

    bindings =
      Map.put(bindings, {"tenant-inline", "rime", "default"}, %{
        "api_key" => "synthetic-rime-private-marker"
      })

    options =
      Keyword.put(options, :credential_source, {TestTenantCredentialSource, {observer, bindings}})

    tts = Keyword.fetch!(options, :text_to_speech)
    providers = Keyword.fetch!(tts, :providers)

    tts =
      Keyword.put(
        tts,
        :providers,
        Map.put(providers, RimeTTSSession, enabled: true, maximum_requests: 4)
      )

    options = Keyword.put(options, :text_to_speech, tts)

    assert {:ok, startup} = PlanStartup.new(plan, options)
    assert {RimeTTSSession, public} = startup.text_to_speech.provider
    assert public[:speaker] == "astra"
    assert public[:sample_rate] == 24_000

    assert [config: config, wire_module: Vxpipe.Providers.Rime.TTSSocket, wire_options: []] =
             startup.text_to_speech.provider_private

    assert config.api_key == "synthetic-rime-private-marker"
    refute inspect(startup) =~ "synthetic-rime-private-marker"
    assert_received {:tenant_credential_resolved, "tenant-inline", "rime", "default"}
  end

  test "Google TTS activation uses the selected voice and keeps its credential private" do
    plan =
      plan(%{
        provider: "google",
        model: "gemini-3.1-flash-tts-preview",
        options: %{voice: "Kore"}
      })

    options = options()
    tts = Keyword.fetch!(options, :text_to_speech)
    providers = Keyword.fetch!(tts, :providers)

    tts =
      Keyword.put(
        tts,
        :providers,
        Map.put(providers, GoogleTTSSession, enabled: true, maximum_requests: 4)
      )

    assert {:ok, startup} = PlanStartup.new(plan, Keyword.put(options, :text_to_speech, tts))
    assert {GoogleTTSSession, public} = startup.text_to_speech.provider
    assert public[:voice] == "Kore"
    assert public[:model] == "gemini-3.1-flash-tts-preview"

    assert [config: config, request_module: Vxpipe.Providers.Google.TTSRequest] =
             startup.text_to_speech.provider_private

    assert config.api_key == "google-tenant-private-marker"
    refute inspect(startup) =~ "google-tenant-private-marker"
    assert_received {:tenant_credential_resolved, "tenant-inline", "google", "default"}
  end

  test "Cartesia TTS activation keeps its scoped credential private and preserves voice and rate" do
    plan = cartesia_plan()
    assert {:ok, startup} = PlanStartup.new(plan, cartesia_options())
    assert {CartesiaTTSSession, public} = startup.text_to_speech.provider
    assert Keyword.fetch!(public, :model) == "sonic-3.6"
    assert Keyword.fetch!(public, :voice) == "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"
    assert Keyword.fetch!(public, :sample_rate) == 16_000

    assert [config: config, request_module: Vxpipe.Providers.Cartesia.TTSRequest] =
             startup.text_to_speech.provider_private

    assert config.api_key == "synthetic-cartesia-private-marker"
    assert config.sample_rate == 16_000
    assert startup.text_to_speech.usage_provider.name == "cartesia"
    refute inspect(startup) =~ "synthetic-cartesia-private-marker"
    refute :erlang.term_to_binary(plan) =~ "synthetic-cartesia-private-marker"
    assert_received {:tenant_credential_resolved, "tenant-inline", "cartesia", "default"}
  end

  test "Cartesia admission rejects private options and unsupported models" do
    for selection <- [
          %{
            provider: "cartesia",
            model: "invented",
            options: %{voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"}
          },
          %{
            provider: "cartesia",
            model: "sonic-3.6",
            options: %{voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4", api_key: "synthetic-key"}
          },
          %{
            provider: "cartesia",
            model: "sonic-3.6",
            options: %{
              voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4",
              endpoint: "https://invalid.example"
            }
          }
        ] do
      source = Vxpipe.CallEngine.CallSpec.CapabilitySelection
      assert {:error, _reason} = source.new(selection, :text_to_speech, ["text_to_speech"])
    end
  end

  test "compiled Cartesia configuration starts a credited session with measured usage" do
    alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session, TTSUsage}
    assert {:ok, startup} = PlanStartup.new(cartesia_plan(), cartesia_options())
    {provider, public} = startup.text_to_speech.provider
    private = startup.text_to_speech.provider_private
    config = %{Keyword.fetch!(private, :config) | endpoint: self()}
    private = [config: config, request_module: Vxpipe.CallEngine.TestRequestTTS]
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: provider,
               options: public,
               private: private,
               usage: true
             )

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    assert {:ok, %{ref: request} = handle} = Session.speak(session, "Hello")

    assert_receive {:vxpipe_speech,
                    %Event{request_ref: ^request, kind: :input_submitted} = submitted}

    assert :ok = Session.ack(session, submitted)
    assert submitted.usage.input_characters == 5
    assert_receive {:test_request_tts_started, worker, "Hello"}
    pcm = :binary.copy(<<1, 0>>, 16_000)
    send(worker, {:audio, pcm})
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session, payload: ^pcm} = audio}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_request_tts_audio_consumed, ^worker, :ok}
    send(worker, :complete)

    assert_receive {:vxpipe_speech,
                    %Event{request_ref: ^request, kind: :completed, usage: %TTSUsage{} = usage} =
                      completed}

    assert :ok = Session.ack(session, completed)
    assert usage.input_characters == 5
    assert usage.generated_bytes == byte_size(pcm)
    assert usage.generation == :completed
    assert usage.provenance == :locally_measured

    assert usage.usage_identity == %{
             provider: :cartesia,
             model: "sonic-3.6",
             provenance: :locally_measured
           }

    assert :ok = Session.settle_output(session, handle, 1_000)
    assert :ok = Session.close(session)
  end

  test "Cartesia startup cannot use disabled settings or another provider's credential" do
    options = cartesia_options()

    assert {:error, _error} =
             PlanStartup.new(cartesia_plan(), Keyword.delete(options, :credential_source))

    disabled = [providers: %{CartesiaTTSSession => [enabled: false, maximum_requests: 4]}]

    assert {:error, _error} =
             PlanStartup.new(cartesia_plan(), Keyword.put(options, :text_to_speech, disabled))

    missing =
      Keyword.put(options, :credential_source, Keyword.fetch!(options(), :credential_source))

    assert {:error, _error} = PlanStartup.new(cartesia_plan(), missing)
  end

  test "Google live STT activation selects 16 kHz PCM and a private credential" do
    plan =
      plan(
        %{provider: "deepgram", model: "flux", options: %{voice: "haley"}},
        %{provider: "google", model: "gemini-3.5-transcribe-live"}
      )

    options = options()
    stt = Keyword.fetch!(options, :speech_to_text)
    providers = Keyword.fetch!(stt, :providers)

    stt =
      Keyword.put(
        stt,
        :providers,
        Map.put(providers, GoogleSTTSession,
          enabled: true,
          media_ingress: [
            maximum_frames: 50,
            maximum_bytes: 262_144,
            maximum_age_ms: 2_000,
            maximum_consecutive_overflows: 5
          ]
        )
      )

    assert {:ok, startup} = PlanStartup.new(plan, Keyword.put(options, :speech_to_text, stt))
    caller = plan.participants["caller"]
    runtime = Map.fetch!(startup.speech_to_text_runtimes, caller.participant_id)
    assert {GoogleSTTSession, public} = runtime.provider
    assert public[:encoding] == :linear16
    assert public[:sample_rate] == 16_000

    assert [config: config, wire_module: Vxpipe.Providers.Google.STTSocket, wire_options: []] =
             runtime.provider_private

    assert config.api_key == "google-tenant-private-marker"
    refute inspect(startup) =~ "google-tenant-private-marker"
  end

  test "compiled Cartesia input launches its scoped semantic session with private credentials" do
    alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
    alias Vxpipe.CallEngine.TestCartesiaSTTTransport, as: Wire

    plan =
      plan(
        %{
          provider: "cartesia",
          model: "sonic-3.6",
          options: %{voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"}
        },
        %{provider: "cartesia", model: "ink-2"}
      )

    options =
      cartesia_options()
      |> Keyword.put(:speech_to_text,
        providers: %{
          CartesiaSTTSession => [
            enabled: true,
            wire_module: Wire,
            wire_options: [observer: self()],
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )

    assert {:ok, startup} = PlanStartup.new(plan, options)
    caller = Map.fetch!(plan.participants, "caller")
    runtime = Map.fetch!(startup.speech_to_text_runtimes, caller.participant_id)
    assert {CartesiaSTTSession, public} = runtime.provider
    assert Keyword.fetch!(public, :sample_rate) == 16_000

    assert Keyword.fetch!(runtime.provider_private, :config).api_key ==
             "synthetic-cartesia-private-marker"

    assert runtime.usage_provider.name == "cartesia"
    refute inspect(startup) =~ "synthetic-cartesia-private-marker"
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: CartesiaSTTSession,
               options: public,
               private: runtime.provider_private
             )

    assert_receive {:cartesia_stt_started, wire, _connection}, 1_000
    :ok = Wire.deliver(wire, %{type: "connected", request_id: "compiled"})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 1_000
    assert :ok = Session.ack(session, ready)
    assert :ok = Session.push_audio(session, <<1, 0>>)
    assert_receive {:cartesia_stt_audio, ^wire, <<1, 0>>}
    :ok = Wire.deliver(wire, %{type: "turn.start", request_id: "compiled"})

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :speech_started, turn_ref: turn} = started},
                   1_000

    assert :ok = Session.ack(session, started)
    :ok = Wire.deliver(wire, %{type: "turn.end", request_id: "compiled", transcript: "Hello."})

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, turn_ref: ^turn, text: "Hello."} =
                      ended},
                   1_000

    assert :ok = Session.ack(session, ended)
  end

  test "ambient private settings cannot rescue an absent tenant source" do
    assert {:error, _error} =
             PlanStartup.new(plan(), Keyword.delete(options(), :credential_source))
  end

  test "obsolete or open-ended speech host settings fail validation" do
    stt_settings =
      options()
      |> Keyword.fetch!(:speech_to_text)
      |> Keyword.fetch!(:providers)
      |> Map.fetch!(FluxSession)

    tts_settings =
      options()
      |> Keyword.fetch!(:text_to_speech)
      |> Keyword.fetch!(:providers)
      |> Map.fetch!(TTSFluxSession)

    invalid_settings = [
      {:speech_to_text, Keyword.put(stt_settings, :provider, FluxSession)},
      {:speech_to_text, Keyword.put(stt_settings, :provider_options, api_key: "obsolete")},
      {:speech_to_text,
       [
         enabled: true,
         providers: %{FluxSession => stt_settings}
       ]},
      {:speech_to_text,
       [
         providers: %{
           FluxSession => stt_settings,
           Vxpipe.CallEngine.SpeechGuideTTSProvider => [enabled: true]
         }
       ]},
      {:speech_to_text,
       [
         providers: %{
           FluxSession => stt_settings,
           Vxpipe.CallEngine.Provider.MorseCodeSTT.Session => [
             enabled: true,
             media_ingress: [],
             provider_private: [ignored: true]
           ]
         }
       ]},
      {:text_to_speech, Keyword.put(tts_settings, :provider, TTSFluxSession)},
      {:text_to_speech, Keyword.put(tts_settings, :provider_private, ignored: true)}
    ]

    for {kind, settings} <- invalid_settings do
      invalid = Keyword.put(options(), kind, settings)

      assert {:error, %{code: :unsupported_call_plan}} =
               PlanStartup.validate(plan(), invalid)
    end
  end

  test "connection speech credentials resolve in an owned preparation worker" do
    plan = plan()
    caller = plan.participants["caller"]

    {TestTenantCredentialSource, {observer, bindings}} =
      Keyword.fetch!(options(), :credential_source)

    options =
      Keyword.put(
        options(),
        :credential_source,
        {TestTenantCredentialSource, {:await, observer, bindings}}
      )

    test = self()

    connection =
      start_supervised!(
        {Task,
         fn ->
           result = ConnectionSpeechPreparation.run(plan, caller, options, 1_000)
           send(test, {:connection_speech_prepared, result})
         end}
      )

    assert_receive {:tenant_credential_resolver_waiting, worker}
    assert worker != connection
    assert worker in Task.Supervisor.children(Vxpipe.CallEngine.ReadinessTaskSupervisor)
    send(worker, :resolve)
    assert_receive {:connection_speech_prepared, {:ok, runtime}}
    assert {FluxSession, _public_stt_config} = runtime.provider

    assert [
             config: configuration,
             wire_module: Vxpipe.Providers.Deepgram.STTSocket,
             wire_options: []
           ] =
             runtime.provider_private

    assert configuration.api_key == "deepgram-tenant-private-marker"
  end

  test "connection speech preparation cancels a credential lookup at its deadline" do
    plan = plan()
    caller = plan.participants["caller"]

    {TestTenantCredentialSource, {observer, bindings}} =
      Keyword.fetch!(options(), :credential_source)

    options =
      Keyword.put(
        options(),
        :credential_source,
        {TestTenantCredentialSource, {:await, observer, bindings}}
      )

    test = self()

    start_supervised!(
      {Task,
       fn ->
         result = ConnectionSpeechPreparation.run(plan, caller, options, 250)
         send(test, {:connection_speech_prepared, result})
       end}
    )

    assert_receive {:tenant_credential_resolver_waiting, worker}
    monitor = Process.monitor(worker)
    assert_receive {:connection_speech_prepared, {:error, :unavailable}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
  end

  test "credential preparation ends when its connection owner exits" do
    plan = plan()
    caller = plan.participants["caller"]

    {TestTenantCredentialSource, {observer, bindings}} =
      Keyword.fetch!(options(), :credential_source)

    options =
      Keyword.put(
        options(),
        :credential_source,
        {TestTenantCredentialSource, {:await, observer, bindings}}
      )

    connection =
      start_supervised!(
        {Task,
         fn ->
           ConnectionSpeechPreparation.run(plan, caller, options, 1_000)
         end}
      )

    assert_receive {:tenant_credential_resolver_waiting, worker}
    monitor = Process.monitor(worker)
    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 200
  end

  test "old serialized plan schema cannot activate" do
    old = %{plan() | schema_version: "20260914.01"}

    assert {:error, %{code: :unsupported_call_plan, details: %{"path" => ["schema_version"]}}} =
             PlanStartup.validate(old, options())
  end

  test "current schema does not admit a decoded selection containing legacy or private fields" do
    plan = plan()
    assistant = plan.participants["assistant"]
    selection = assistant.capabilities.model_inference

    for injected <- [
          Map.put(selection, :profile, "old-model"),
          %{selection | provider_options: %{"api_key" => "private-marker"}}
        ] do
      capabilities = %{assistant.capabilities | model_inference: injected}

      changed = %{
        plan
        | participants:
            Map.put(plan.participants, "assistant", %{assistant | capabilities: capabilities})
      }

      assert {:error, %{code: :unsupported_call_plan}} = PlanStartup.validate(changed, options())
    end
  end

  defp cartesia_plan do
    plan(%{
      provider: "cartesia",
      model: "sonic-3.6",
      options: %{voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4", sample_rate: 16_000}
    })
  end

  defp cartesia_options do
    options = options()

    {TestTenantCredentialSource, {observer, bindings}} =
      Keyword.fetch!(options, :credential_source)

    bindings =
      Map.put(bindings, {"tenant-inline", "cartesia", "default"}, %{
        "api_key" => "synthetic-cartesia-private-marker"
      })

    options
    |> Keyword.put(:credential_source, {TestTenantCredentialSource, {observer, bindings}})
    |> Keyword.put(:text_to_speech,
      providers: %{CartesiaTTSSession => [enabled: true, maximum_requests: 4]}
    )
  end

  defp options do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    bindings = %{
      {"tenant-inline", "google", "default"} => %{"api_key" => "google-tenant-private-marker"},
      {"tenant-inline", "deepgram", "default"} => %{"api_key" => "deepgram-tenant-private-marker"}
    }

    [
      owner: self(),
      credential_source: {TestTenantCredentialSource, {self(), bindings}},
      agent_runtime:
        settings
        |> Keyword.fetch!(:agent_runtime)
        |> Keyword.put(:model_provider_options, api_key: "retired-private-marker"),
      speech_to_text: [
        providers: %{
          FluxSession => [
            enabled: true,
            wire_options: [],
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      ],
      text_to_speech: [
        providers: %{
          TTSFluxSession => [
            enabled: true,
            wire_options: [],
            maximum_requests: 4
          ]
        }
      ]
    ]
  end

  defp plan(
         tts_selection \\ %{
           provider: "deepgram",
           model: "flux",
           options: %{voice: "haley"}
         },
         stt_selection \\ %{
           provider: "deepgram",
           model: "flux-general-en",
           options: %{encoding: "opus", sample_rate: 48_000}
         }
       ) do
    source = %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          speech_to_text: stt_selection,
          model_inference: %{
            provider: "google",
            model: "gemini-2.5-flash",
            options: %{temperature: 0.2}
          },
          text_to_speech: tts_selection
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }

    {:ok, call_spec} = CallSpec.new(source, resource_id: "activation", revision: 1)

    {:ok, invocation} =
      CallInvocation.new(
        %{call_spec: %{id: "activation", revision: 1}, transport: %{type: "web"}},
        tenant_id: "tenant-inline",
        actor_id: "operator-inline"
      )

    {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})
    plan
  end
end
