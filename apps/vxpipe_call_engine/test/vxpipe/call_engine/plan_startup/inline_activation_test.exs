defmodule Vxpipe.CallEngine.PlanStartup.InlineActivationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, PlanStartup}
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
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
    assert {Flux, stt_config} = stt.provider
    assert stt_config.api_key == "deepgram-tenant-private-marker"
    assert {FluxTextToSpeech, tts_config} = startup.text_to_speech.provider
    assert tts_config.api_key == "deepgram-tenant-private-marker"

    for provider <- ["google", "deepgram"] do
      assert_received {:tenant_credential_resolved, "tenant-inline", ^provider, "default"}
    end

    refute :erlang.term_to_binary(plan) =~ "private-marker"
  end

  test "ambient private settings cannot rescue an absent tenant source" do
    assert {:error, _error} =
             PlanStartup.new(plan(), Keyword.delete(options(), :credential_source))
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
    assert {Flux, configuration} = runtime.provider
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
        enabled: true,
        provider: Flux,
        provider_options: [api_key: "retired-private-marker"],
        transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxSocket, []},
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ],
      text_to_speech: [
        enabled: true,
        provider: FluxTextToSpeech,
        provider_options: [api_key: "retired-private-marker"],
        transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechSocket, []},
        maximum_requests: 4
      ]
    ]
  end

  defp plan do
    source = %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          speech_to_text: %{
            provider: "deepgram",
            model: "flux-general-en",
            options: %{encoding: "opus", sample_rate: 48_000}
          },
          model_inference: %{
            provider: "google",
            model: "gemini-2.5-flash",
            options: %{temperature: 0.2}
          },
          text_to_speech: %{
            provider: "deepgram",
            model: "flux-haley-en",
            options: %{encoding: "linear16", sample_rate: 48_000}
          }
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

    {:ok, definition} = CallDefinition.new(source, resource_id: "activation", revision: 1)

    {:ok, invocation} =
      CallInvocation.new(
        %{call_definition: %{id: "activation", revision: 1}, transport: %{type: "web"}},
        tenant_id: "tenant-inline",
        actor_id: "operator-inline"
      )

    {:ok, plan} = DefinitionCompiler.compile(definition, invocation, %{host_tools: %{}})
    plan
  end
end
