defmodule Vxpipe.CallEngine.PlanStartup.DestinationCredentialsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, PlanStartup}
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{DestinationPreparer, Runtime}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request
  alias Vxpipe.CallEngine.{TestTenantCredentialSource, TestTurnCall}

  test "destination constructors use whole selections and isolate identical names across tenants" do
    bindings = Map.merge(bindings("tenant-one"), bindings("tenant-two"))
    options = options({self(), bindings})

    for tenant <- ["tenant-one", "tenant-two"] do
      plan = plan(tenant)
      agent = Map.fetch!(plan.participants, "agent")
      human = Map.fetch!(plan.participants, "human")

      assert {:ok, destination} = PlanStartup.agent_destination(plan, agent, options)
      model = Keyword.fetch!(destination.agent_activation, :model)
      assert model.api_key == tenant <> "-model-private-marker"
      assert model.model.id == "gemini-2.5-flash-lite"
      assert Keyword.fetch!(model.generation_options, :max_tokens) == 64
      refute Keyword.has_key?(model.generation_options, :temperature)

      assert {FluxTextToSpeech, voice} = destination.text_to_speech.provider
      assert voice.api_key == tenant <> "-voice-private-marker"
      assert voice.model == "flux-haley-en"
      assert voice.sample_rate == 24_000

      assert {:ok, listener} = PlanStartup.human_destination(plan, human, options)
      assert {Flux, recognition} = listener.speech_to_text.provider
      assert recognition.api_key == tenant <> "-listener-private-marker"
      assert recognition.encoding == :linear16
      assert recognition.sample_rate == 16_000

      for {provider, name} <- [
            {"google", "destination-model"},
            {"deepgram", "destination-voice"},
            {"deepgram", "destination-listener"}
          ] do
        assert_received {:tenant_credential_resolved, ^tenant, ^provider, ^name}
      end

      refute inspect({destination, listener}) =~ "private-marker"

      refute :erlang.term_to_binary(destination.text_to_speech.asset_cache_identity) =~
               "private-marker"

      refute :erlang.term_to_binary(plan) =~ "private-marker"
    end

    refute_received {:tenant_credential_resolved, _, _, "default"}
  end

  test "every new destination construction rechecks the binding instead of retaining its payload" do
    tenant = "tenant-fresh"
    plan = plan(tenant)
    agent = Map.fetch!(plan.participants, "agent")
    human = Map.fetch!(plan.participants, "human")
    store = start_supervised!({Agent, fn -> bindings(tenant) end})
    options = options({:store, self(), store})
    assert {:ok, first} = PlanStartup.agent_destination(plan, agent, options)
    assert {:ok, first_listener} = PlanStartup.human_destination(plan, human, options)

    Agent.update(store, fn bindings ->
      bindings
      |> Map.put({tenant, "google", "destination-model"}, %{
        "api_key" => "new-model-private-marker"
      })
      |> Map.put({tenant, "deepgram", "destination-voice"}, %{
        "api_key" => "new-voice-private-marker"
      })
      |> Map.put({tenant, "deepgram", "destination-listener"}, %{
        "api_key" => "new-listener-private-marker"
      })
    end)

    assert {:ok, second} = PlanStartup.agent_destination(plan, agent, options)
    assert {:ok, second_listener} = PlanStartup.human_destination(plan, human, options)

    assert Keyword.fetch!(first.agent_activation, :model).api_key ==
             tenant <> "-model-private-marker"

    assert Keyword.fetch!(second.agent_activation, :model).api_key == "new-model-private-marker"
    assert {FluxTextToSpeech, voice} = second.text_to_speech.provider
    assert voice.api_key == "new-voice-private-marker"
    assert {Flux, old_listener} = first_listener.speech_to_text.provider
    assert old_listener.api_key == tenant <> "-listener-private-marker"
    assert {Flux, new_listener} = second_listener.speech_to_text.provider
    assert new_listener.api_key == "new-listener-private-marker"
    refute inspect(second) =~ "private-marker"
  end

  for {provider, name, destination_key} <- [
        {"google", "destination-model", "agent"},
        {"deepgram", "destination-voice", "agent"},
        {"deepgram", "destination-listener", "human"}
      ] do
    @binding {provider, name}
    @destination_key destination_key

    test "unavailable #{@binding |> elem(1)} fails preparation before destination clients start" do
      tenant = "tenant-failure"
      plan = plan(tenant)
      all = bindings(tenant)
      assert {:ok, startup} = PlanStartup.new(plan, options({self(), all}))
      {provider, name} = @binding
      missing = Map.delete(all, {tenant, provider, name})
      runtime = %Runtime{plan: plan, startup_options: options({self(), missing})}
      destination = Map.fetch!(plan.participants, @destination_key)
      request = request(plan, destination)

      assert {:error, :destination_plan_unavailable} =
               DestinationPreparer.prepare(
                 request,
                 runtime,
                 destination,
                 true,
                 [],
                 startup.text_to_speech,
                 System.monotonic_time(:millisecond) + 1_000
               )

      assert_received {:tenant_credential_resolved, ^tenant, ^provider, ^name}
      refute_received {:test_tts_transport_started, _, _}
      refute_received {:test_stt_transport_started, _, _}
      refute inspect(request) =~ "private-marker"
    end
  end

  defp bindings(tenant) do
    Map.new(
      [
        {"google", "default", "default-model"},
        {"deepgram", "default", "default-speech"},
        {"google", "destination-model", "model"},
        {"deepgram", "destination-voice", "voice"},
        {"deepgram", "destination-listener", "listener"}
      ],
      fn {provider, name, label} ->
        {{tenant, provider, name}, %{"api_key" => tenant <> "-" <> label <> "-private-marker"}}
      end
    )
  end

  defp options(context) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    [
      owner: self(),
      credential_source: {TestTenantCredentialSource, context},
      agent_runtime: Keyword.fetch!(settings, :agent_runtime),
      speech_to_text: [
        enabled: true,
        provider: Flux,
        provider_options: [api_key: "retired-private-marker"],
        transport: {Vxpipe.CallEngine.TestSpeechToTextTransport, [observer: self()]},
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
        transport: {Vxpipe.CallEngine.TestTextToSpeechTransport, [observer: self()]},
        maximum_requests: 4
      ]
    ]
  end

  defp plan(tenant) do
    source =
      TestTurnCall.definition()
      |> put_in([:defaults, :capabilities], %{
        model_inference: %{
          provider: "google",
          model: "gemini-2.5-flash",
          options: %{temperature: 0.2}
        },
        speech_to_text: speech("flux-general-en", "default", "opus", 48_000),
        text_to_speech: speech("flux-application-voice", "default", "linear16", 48_000)
      })
      |> put_in([:participants, "agent"], %{
        type: "agent",
        prompt: "Destination prompt.",
        first_message: %{mode: "wait_for_input"},
        capabilities: %{
          model_inference: %{
            provider: "google",
            model: "gemini-2.5-flash-lite",
            credential_name: "destination-model",
            options: %{max_tokens: 64}
          },
          text_to_speech: speech("flux-haley-en", "destination-voice", "linear16", 24_000)
        },
        tools: %{},
        transfers: []
      })
      |> put_in([:participants, "human"], %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "transfer"},
        capabilities: %{
          speech_to_text: speech("flux-general-en", "destination-listener", "linear16", 16_000)
        }
      })
      |> put_in([:participants, "receiver", :transfers], ["agent", "human"])

    assert {:ok, definition} =
             CallDefinition.new(source, resource_id: "destinations", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_definition: %{id: "destinations", revision: 1}, transport: %{type: "web"}},
               tenant_id: tenant,
               actor_id: "operator"
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, %{host_tools: %{}})
    plan
  end

  defp speech(model, name, encoding, sample_rate),
    do: %{
      provider: "deepgram",
      model: model,
      credential_name: name,
      options: %{encoding: encoding, sample_rate: sample_rate}
    }

  defp request(plan, destination) do
    source = Map.fetch!(plan.participants, plan.entry_receiver)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    %Request{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: "not-started",
      source_definition_key: source.definition_key,
      source_participant_id: source.participant_id,
      source_activation_id: source.activation_id,
      source_capability: self(),
      caller_participant_id: caller.participant_id,
      connection_id: "not-attached",
      command_id: "command-destination",
      correlation_id: "turn-destination",
      tool_call_id: "transfer",
      destination_definition_key: destination.definition_key,
      destination_participant_id: destination.participant_id,
      reason: "Help the caller."
    }
  end
end
