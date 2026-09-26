defmodule Vxpipe.CallEngine.PlanStartup.STSConfigurationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.PlanStartup.SpeechToSpeechActivation
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.SpeechToSpeechRuntime
  alias Vxpipe.CallEngine.STSContextTool
  alias Vxpipe.Providers.Google.{STS, STSSession}
  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

  test "OpenAI activation keeps tenant auth, prompt and tools private" do
    options = [api_key: "synthetic-openai-secret", backend_model: "gpt-5.6-luna"]
    assert {:ok, ^options} = SpeechToSpeechRuntime.configure(GPTLiveSession, options)
    assert {:ok, activation} = SpeechToSpeechActivation.resolve(nil, participant(), [])

    assert {:ok, {GPTLiveSession, public}, private} =
             SpeechToSpeechRuntime.provider({GPTLiveSession, options}, [], activation)

    refute Keyword.has_key?(public, :api_key)
    assert {:ok, _descriptor} = GPTLiveSession.configure(public)
    config = Keyword.fetch!(private, :config)
    start = GPTLive.start(config, [])
    assert start["session"]["instructions"] == "private-prompt-marker"

    assert [%{"type" => "function", "name" => "echo_context"}] =
             Enum.map(
               start["session"]["delegation"]["responses"]["tools"],
               &Map.take(&1, ["type", "name"])
             )

    for visible <- [public, private, config] do
      refute inspect(visible) =~ "synthetic-openai-secret"
      refute inspect(visible) =~ "private-prompt-marker"
    end
  end

  test "authenticated provider resolution validates private options before the public/private split" do
    options = [api_key: "synthetic-private-key", model: "gemini-3.8-live"]
    assert {:ok, ^options} = SpeechToSpeechRuntime.configure(STSSession, options)

    assert {:error, :invalid_configuration} =
             SpeechToSpeechRuntime.configure(STSSession, api_key: "")

    assert {:ok, activation} = SpeechToSpeechActivation.resolve(nil, participant(), [])

    assert {:ok, {_provider, public}, private} =
             SpeechToSpeechRuntime.provider({STSSession, options}, [], activation)

    refute Keyword.has_key?(public, :api_key)
    assert Keyword.fetch!(private, :config).api_key == "synthetic-private-key"
  end

  test "activation carries only the pinned prompt and authorized model-visible tools privately" do
    participant = participant()
    assert {:ok, activation} = SpeechToSpeechActivation.resolve(nil, participant, [])

    assert {:ok, {STSSession, public}, private} =
             SpeechToSpeechRuntime.provider(
               {STSSession, [api_key: "synthetic-private-key"]},
               [],
               activation
             )

    config = Keyword.fetch!(private, :config)
    setup = STS.setup(config)["setup"]
    assert setup["systemInstruction"] == %{"parts" => [%{"text" => participant.prompt}]}
    assert setup["tools"] == [%{"functionDeclarations" => [declaration()]}]
    assert {:ok, descriptor} = STSSession.configure(public)

    for visible <- [public, descriptor, activation, config, private] do
      refute inspect(visible) =~ "private-prompt-marker"
      refute inspect(visible) =~ "Return public invocation identity"
      refute inspect(visible) =~ "synthetic-private-key"
    end

    refute JSON.encode!(setup) =~ "handler"
    refute JSON.encode!(setup) =~ "compiled_schema"
  end

  test "invalid bindings and unavailable variable activation fail explicitly" do
    receiver = participant()
    bad = %{receiver | tools: %{"unapproved_alias" => receiver.tools["echo_context"]}}
    assert {:error, :invalid_configuration} = SpeechToSpeechActivation.resolve(nil, bad, [])
    bad = %{receiver | variable_permissions: %{grants: %{"private" => :read}}}
    assert {:error, :invalid_configuration} = SpeechToSpeechActivation.resolve(nil, bad, [])
  end

  test "empty allowlist stays empty and malformed or oversized prompt is rejected" do
    receiver = %{participant() | tools: %{}}
    assert {:ok, activation} = SpeechToSpeechActivation.resolve(nil, receiver, [])

    assert {:ok, {_module, _public}, private} =
             SpeechToSpeechRuntime.provider({STSSession, [api_key: "synthetic"]}, [], activation)

    assert STS.setup(Keyword.fetch!(private, :config))["setup"]["tools"] == []

    for prompt <- [nil, 42, <<255>>, String.duplicate("x", 65_537)] do
      assert {:error, :invalid_configuration} =
               SpeechToSpeechActivation.resolve(nil, %{receiver | prompt: prompt}, [])
    end
  end

  test "variable permission resolution advertises only the permitted actions" do
    plan = %{tenant_id: "tenant", room_id: "room"}

    receiver =
      participant()
      |> Map.merge(%{
        participant_id: "agent",
        activation_id: "activation",
        variable_permissions: %{grants: %{"private-section" => :read}}
      })

    options = [call_variables: self(), incarnation_id: "incarnation"]
    assert {:ok, activation} = SpeechToSpeechActivation.resolve(plan, receiver, options)
    assert Enum.map(activation.tools, & &1.name) == ["echo_context", "read_variables"]

    assert {:ok, {_provider, _public}, private} =
             SpeechToSpeechRuntime.provider({STSSession, [api_key: "synthetic"]}, [], activation)

    [group] = STS.setup(Keyword.fetch!(private, :config))["setup"]["tools"]
    [echo, read] = group["functionDeclarations"]
    assert echo == declaration()

    assert read["parametersJsonSchema"] ==
             Vxpipe.CallEngine.Tool.ReadVariables.definition().parameters

    refute inspect(private) =~ "private-section"
    refute JSON.encode!(group) =~ "private-section"
    refute JSON.encode!(group) =~ "update_variable"
  end

  test "unavailable remote owner and unsupported overrides fail without leaking configuration" do
    {_catalog, remote} = Vxpipe.CallEngine.RemoteMCPFixture.binding!(self(), self(), "private")
    receiver = %{participant() | tools: %{"customer_lookup" => remote}}
    assert {:error, :invalid_configuration} = SpeechToSpeechActivation.resolve(nil, receiver, [])
    assert {:ok, activation} = SpeechToSpeechActivation.resolve(nil, participant(), [])

    for options <- [
          [api_key: "synthetic", tools: []],
          [api_key: "synthetic", system_prompt: "override"]
        ] do
      assert {:error, :invalid_configuration} =
               SpeechToSpeechRuntime.provider({STSSession, options}, [], activation)
    end

    for settings <- [[wire_module: :unsupported], [transport: :unsupported]] do
      assert {:error, :invalid_configuration} =
               SpeechToSpeechRuntime.provider(
                 {STSSession, [api_key: "synthetic"]},
                 settings,
                 activation
               )
    end
  end

  defp participant do
    %{
      prompt: "private-prompt-marker",
      variable_permissions: %{grants: %{}},
      tools: %{
        "echo_context" => %ToolBinding{
          name: "echo_context",
          type: :host,
          conversation_mode: :blocking,
          action: STSContextTool
        }
      }
    }
  end

  defp declaration do
    definition = STSContextTool.definition()

    %{
      "name" => definition.name,
      "description" => definition.description,
      "parametersJsonSchema" => definition.parameters
    }
  end
end
