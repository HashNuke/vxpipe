defmodule Vxpipe.CallEngine.Speech.ConversationLanguagesRimeCodaTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.Speech.ConversationLanguages
  alias Vxpipe.CallEngine.Speech.ModelLanguages

  test "rime coda emits en when an English preference exists" do
    assert ConversationLanguages.resolve(["en"], :tts, "rime", "coda") == ["en"]
    assert ConversationLanguages.resolve(["en-US"], :tts, "rime", "coda") == ["en"]
    assert ConversationLanguages.resolve(["en-GB"], :tts, "rime", "coda") == ["en"]
    assert ConversationLanguages.resolve(["es-MX", "en-GB"], :tts, "rime", "coda") == ["en"]
  end

  test "rime coda omits call-wide hints without an English preference" do
    assert ConversationLanguages.resolve(["es-MX"], :tts, "rime", "coda") == []
    assert ConversationLanguages.resolve(["fr-FR", "es-MX"], :tts, "rime", "coda") == []
    assert ConversationLanguages.resolve([], :tts, "rime", "coda") == []
    assert ConversationLanguages.resolve(nil, :tts, "rime", "coda") == []
  end

  test "rime coda does not conflate Cantonese or Mandarin with English" do
    assert ConversationLanguages.resolve(["yue-Hant-HK"], :tts, "rime", "coda") == []
    assert ConversationLanguages.resolve(["cmn-Hans-CN"], :tts, "rime", "coda") == []
    assert ConversationLanguages.resolve(["zh-CN"], :tts, "rime", "coda") == []
  end

  test "legacy per-model rime coda settings still accept descriptor languages" do
    assert ModelLanguages.valid?(:tts, "rime", "coda", ["en"])
    assert ModelLanguages.valid?(:tts, "rime", "coda", ["es"])
  end

  test "rime coda pin uses actual selection speaker" do
    astra = plan_with_tts(%{"speaker" => "astra"})
    assert pinned_languages(astra, ["es-MX", "en-GB"]) == ["en"]
    assert pinned_languages(astra, ["en-US"]) == ["en"]

    abril = plan_with_tts(%{"speaker" => "abril"})
    assert pinned_languages(abril, ["es-MX", "en-GB"]) == ["es"]
    assert pinned_languages(abril, ["en-GB"]) == []

    missing = plan_with_tts(%{})
    assert pinned_languages(missing, ["es-MX", "en-GB"]) == ["en"]

    unknown = plan_with_tts(%{"speaker" => "unknown-voice-xyz"})
    assert pinned_languages(unknown, ["es-MX", "en-GB"]) == []
    assert pinned_languages(unknown, ["en-US"]) == []

    for withheld <- ["alfhild", "pola", "potrero", "solana", "yukiko"] do
      plan = plan_with_tts(%{"speaker" => withheld})
      assert pinned_languages(plan, ["en-US", "es-MX"]) == []
    end
  end

  test "historical astra/en config still validates and pins English" do
    input = %{provider: "rime", model: "coda", languages: ["en"], options: %{speaker: "astra"}}
    assert {:ok, selection} = CapabilitySelection.new(input, :text_to_speech, [])
    assert {:ok, opts} = Vxpipe.CallEngine.CapabilityCatalog.speech_options(selection)
    assert opts[:speaker] == "astra"

    plan = plan_with_tts(%{"speaker" => "astra"})
    assert pinned_languages(plan, ["en"]) == ["en"]
  end

  defp rime_selection(options) do
    %CapabilitySelection{
      kind: :text_to_speech,
      provider: "rime",
      model: "coda",
      credential_name: "default",
      options: options,
      provider_options: %{},
      languages: []
    }
  end

  defp plan_with_tts(options) do
    capabilities = %ResolvedCallPlan.Capabilities{
      speech_to_text: nil,
      model_inference: nil,
      text_to_speech: rime_selection(options),
      speech_to_speech: nil,
      output_speech_to_text: nil
    }

    participant = %ResolvedCallPlan.Participant{
      call_spec_key: "assistant",
      participant_id: "participant-rime",
      activation_id: nil,
      kind: :agent,
      description: nil,
      connection: nil,
      transfer_notice: nil,
      prompt: nil,
      first_message: nil,
      first_message_text: nil,
      capabilities: capabilities,
      while_present: nil,
      tools: %{},
      transfers: [],
      transfer_history: nil,
      variable_permissions: nil
    }

    %ResolvedCallPlan{
      call_spec_id: "spec-rime",
      call_spec_revision: 1,
      schema_version: "test",
      tenant_id: "tenant-rime",
      actor_id: "actor-rime",
      call_id: "call-rime",
      room_id: "room-rime",
      transport: :web,
      entry_caller: "assistant",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: nil,
      participants: %{"assistant" => participant},
      transfer_policy: nil,
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 60_000
    }
  end

  defp pinned_languages(plan, preferences) do
    plan
    |> ConversationLanguages.pin(preferences)
    |> Map.fetch!(:participants)
    |> Map.fetch!("assistant")
    |> Map.fetch!(:capabilities)
    |> Map.fetch!(:text_to_speech)
    |> Map.fetch!(:languages)
  end
end
