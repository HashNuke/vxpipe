defmodule Vxpipe.CallEngine.CallSpecConversationLanguagesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallSpecCompiler, CallInvocation}

  defp base_source(overrides \\ %{}) do
    Map.merge(
      %{
        schema_version: "20260915.01",
        name: "Example",
        entry_caller: "caller",
        entry_receiver: "assistant",
        defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
        participants: %{
          "caller" => %{
            type: "human",
            connection: %{service: "web", mode: "receive", admission: "start_call"}
          },
          "assistant" => %{
            type: "agent",
            prompt: "Help the caller.",
            first_message: %{mode: "wait_for_input"},
            tools: %{},
            transfers: []
          }
        }
      },
      overrides
    )
  end

  defp new_spec(source) do
    CallSpec.new(source, resource_id: "spec-conversation", revision: 1)
  end

  test "absent preserves legacy per-model languages" do
    source =
      base_source()
      |> put_in([:defaults, :capabilities, :speech_to_text], %{
        provider: "elevenlabs",
        model: "scribe_v2_realtime",
        languages: ["en"]
      })

    assert {:ok, spec} = new_spec(source)
    assert spec.conversation_languages == nil
  end

  test "empty list means automatic and valid ordered subset is stored in order" do
    source = Map.put(base_source(), :conversation_languages, [])
    assert {:ok, spec} = new_spec(source)
    assert spec.conversation_languages == []

    source =
      Map.put(base_source(), :conversation_languages, ["es-MX", "en-GB", "en-US"])

    assert {:ok, spec} = new_spec(source)
    assert spec.conversation_languages == ["es-MX", "en-GB", "en-US"]
  end

  test "duplicate, unknown and non-list preferences are rejected" do
    for invalid <- [
          ["en", "en"],
          ["zz"],
          "en",
          ["en", 1],
          %{languages: ["en"]}
        ] do
      source = Map.put(base_source(), :conversation_languages, invalid)
      assert {:error, %{details: %{"path" => ["conversation_languages"]}}} = new_spec(source)
    end
  end

  test "explicit call-wide preferences can supersede saved legacy hints" do
    base = Map.put(base_source(), :conversation_languages, ["en", "es"])

    conflicted =
      put_in(base, [:defaults, :capabilities, :speech_to_text], %{
        provider: "elevenlabs",
        model: "scribe_v2_realtime",
        languages: ["en"]
      })

    assert {:ok, _} = new_spec(conflicted)

    legacy_option =
      put_in(base, [:defaults, :capabilities, :speech_to_text], %{
        provider: "elevenlabs",
        model: "scribe_v2_realtime",
        options: %{language_code: "fr"}
      })

    assert {:ok, automatic} = new_spec(Map.put(legacy_option, :conversation_languages, []))
    plan = compile!(automatic)
    selection = plan.participants["caller"].capabilities.speech_to_text
    assert {:ok, opts} = Vxpipe.CallEngine.CapabilityCatalog.speech_options(selection)
    assert is_nil(opts[:language_code])
  end

  test "compilation pins effective hints and preserves stored preferences" do
    source =
      base_source(%{conversation_languages: ["es-MX", "en-GB", "pt-BR"]})
      |> put_in([:defaults, :capabilities, :speech_to_text], %{
        provider: "elevenlabs",
        model: "scribe_v2_realtime"
      })

    assert {:ok, spec} = new_spec(source)
    plan = compile!(spec)
    assert plan.participants["caller"].capabilities.speech_to_text.languages == ["es", "en", "pt"]
    assert spec.conversation_languages == ["es-MX", "en-GB", "pt-BR"]
  end

  defp compile!(spec) do
    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "spec-conversation", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-conversation-01",
               actor_id: "actor-01",
               call_id: "call-01",
               room_id: "room-01"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    plan
  end

  defp compile(spec) do
    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "spec-conversation", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-conversation-01",
               actor_id: "actor-01",
               call_id: "call-01",
               room_id: "room-01"
             )

    CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
  end

  test "compiler revalidates forged root conversation_languages with a path-aware error" do
    assert {:ok, spec} = new_spec(Map.put(base_source(), :conversation_languages, ["en"]))

    for invalid <- [
          ["en", "en"],
          ["zz"],
          "en",
          ["en", 1],
          %{languages: ["en"]},
          ["en" | "es"]
        ] do
      forged = %{spec | conversation_languages: invalid}

      assert {:error,
              %Vxpipe.CallEngine.Error{
                code: :call_spec_resolution_failed,
                details: %{"path" => ["conversation_languages"]}
              }} = compile(forged)
    end
  end

  test "compiler accepts old structs without the conversation_languages field" do
    assert {:ok, spec} = new_spec(Map.put(base_source(), :conversation_languages, ["en"]))
    legacy = Map.delete(spec, :conversation_languages)
    refute Map.has_key?(legacy, :conversation_languages)

    assert {:ok, plan} = compile(legacy)
    assert %Vxpipe.CallEngine.ResolvedCallPlan{} = plan
  end

  test "legacy flux alias cutover preserves English-only wiring without root preferences" do
    historical =
      put_in(base_source(), [:defaults, :capabilities, :speech_to_text], %{
        provider: "deepgram",
        model: "flux",
        languages: ["en"],
        options: %{encoding: "linear16", sample_rate: 16_000}
      })

    query_pairs = fn selection ->
      assert {:ok, options} =
               Vxpipe.CallEngine.CapabilityCatalog.speech_options(selection)

      assert {:ok, config} =
               Vxpipe.Providers.Deepgram.Flux.new(Keyword.put(options, :api_key, "regression"))

      config
      |> Vxpipe.Providers.Deepgram.Flux.connection_options()
      |> Map.fetch!(:url)
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.query_decoder()
      |> Enum.to_list()
    end

    assert {:ok, omitted_spec} = new_spec(historical)
    assert omitted_spec.conversation_languages == nil

    omitted_selection =
      compile!(omitted_spec).participants["caller"].capabilities.speech_to_text

    assert omitted_selection.model == "flux"
    assert omitted_selection.languages == ["en"]

    omitted_pairs = query_pairs.(omitted_selection)
    assert {"model", "flux-general-en"} in omitted_pairs
    assert for({"language_hint", code} <- omitted_pairs, do: code) == []

    assert {:ok, rooted_spec} = new_spec(Map.put(historical, :conversation_languages, ["en"]))

    rooted_selection =
      compile!(rooted_spec).participants["caller"].capabilities.speech_to_text

    assert rooted_selection.model == "flux-general-multi"
    assert rooted_selection.languages == ["en"]

    rooted_pairs = query_pairs.(rooted_selection)
    assert {"model", "flux-general-multi"} in rooted_pairs
    assert for({"language_hint", code} <- rooted_pairs, do: code) == ["en"]

    explicit =
      put_in(base_source(), [:defaults, :capabilities, :speech_to_text], %{
        provider: "deepgram",
        model: "flux-general-multi",
        languages: ["en"],
        options: %{encoding: "linear16", sample_rate: 16_000}
      })

    for source <- [explicit, Map.put(explicit, :conversation_languages, ["en"])] do
      assert {:ok, spec} = new_spec(source)

      selection = compile!(spec).participants["caller"].capabilities.speech_to_text
      assert selection.model == "flux-general-multi"
      assert selection.languages == ["en"]

      pairs = query_pairs.(selection)
      assert {"model", "flux-general-multi"} in pairs
      assert for({"language_hint", code} <- pairs, do: code) == ["en"]
    end
  end
end
