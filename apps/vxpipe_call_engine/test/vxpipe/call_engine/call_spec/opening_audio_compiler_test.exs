defmodule Vxpipe.CallEngine.CallSpec.OpeningAudioCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler, Error}
  alias Vxpipe.CallEngine.CallSpec.OpeningAudio
  alias Vxpipe.CallEngine.CallSpec.CapabilityRequirements

  test "current text openings pin the call's default TTS and credential even for human handlers" do
    voice = %{
      provider: "deepgram",
      model: "flux-haley-en",
      credential_name: "opening-voice",
      options: %{encoding: "linear16", sample_rate: 24_000}
    }

    input =
      current_input()
      |> put_in([:defaults, :capabilities], %{text_to_speech: voice})
      |> put_in([:participants, "reception"], %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "start_call"}
      })

    assert {:ok, spec} = CallSpec.new(input, resource_id: "support", revision: 7)

    assert [{selection, ["defaults", "capabilities", "text_to_speech"]}] =
             CapabilityRequirements.credentials(spec)

    assert selection.credential_name == "opening-voice"
    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation(), registries())
    assert plan.opening_audio.text_to_speech == selection
    assert plan.opening_audio.text == "Notice"
    assert plan.participants["caller"].capabilities.text_to_speech == nil

    invalid = put_in(input, [:opening_audio, :text_to_speech], voice)

    assert {:error, %Error{details: %{"path" => ["opening_audio", "text_to_speech"]}}} =
             CallSpec.new(invalid, resource_id: "support", revision: 7)

    legacy = Map.put(input, :schema_version, "20261004.01")

    assert {:error, %Error{details: %{"path" => ["opening_audio", "text_to_speech"]}}} =
             CallSpec.new(legacy, resource_id: "support", revision: 7)

    explicit_voice = %{provider: "morse", model: "morse"}

    assert {:ok, spec} =
             CallSpec.new(put_in(legacy, [:opening_audio, :text_to_speech], explicit_voice),
               resource_id: "support",
               revision: 7
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation(), registries())
    assert plan.opening_audio.text_to_speech.provider == "morse"
  end

  test "an STS call default prevents text openings even with a default TTS and only human participants" do
    speech = %{provider: "morse", model: "morse"}

    source =
      current_input()
      |> put_in([:defaults, :capabilities], %{speech_to_speech: speech, text_to_speech: speech})
      |> put_in([:participants, "reception"], current_input().participants["caller"])

    assert {:ok, spec} = CallSpec.new(source, resource_id: "support", revision: 7)

    assert {:error, %Error{details: %{"path" => ["opening_audio", "type"], "reason" => reason}}} =
             CallSpecCompiler.compile(spec, invocation(), registries())

    assert reason =~ "speech-to-speech"
  end

  test "current text opening drafts accept missing TTS and STS defaults but cannot execute" do
    for capabilities <- [
          %{model_inference: %{provider: "fixture", model: "test"}},
          %{speech_to_speech: %{provider: "morse", model: "morse"}}
        ] do
      input = put_in(current_input(), [:defaults, :capabilities], capabilities)
      assert {:ok, spec} = CallSpec.new(input, resource_id: "support", revision: 7)

      assert {:error, %Error{details: %{"path" => ["opening_audio", "type"]}}} =
               CallSpecCompiler.compile(spec, invocation(), registries())

      for opening <- [nil, %{type: "file_url", url: "https://assets.example.test/notice.wav"}] do
        assert {:ok, spec} =
                 CallSpec.new(Map.put(input, :opening_audio, opening),
                   resource_id: "support",
                   revision: 7
                 )

        assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation(), registries())
        assert (plan.opening_audio && plan.opening_audio.type) == (opening && :file_url)
      end
    end
  end

  test "current incoming and outgoing entry humans inherit call settings while other humans retain overrides" do
    speech = %{provider: "morse", model: "morse"}

    incoming =
      current_input()
      |> Map.delete(:opening_audio)
      |> put_in([:defaults, :capabilities, :speech_to_text], speech)

    outgoing =
      incoming
      |> Map.delete(:incoming_call)
      |> Map.put(:outgoing_call, %{callee: "caller", handled_by: "reception"})
      |> put_in([:participants, "caller", :connection], %{service: "phone", mode: "dial"})

    for input <- [incoming, outgoing] do
      human = %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "transfer"},
        capabilities: %{speech_to_text: speech},
        while_present: %{record_audio: false}
      }

      input = put_in(input, [:participants, "support-human"], human)
      assert {:ok, spec} = CallSpec.new(input, resource_id: "support", revision: 7)
      assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation(), registries())

      assert plan.participants["caller"].capabilities.speech_to_text ==
               spec.default_capabilities.speech_to_text

      assert plan.participants["caller"].while_present.record_audio == :inherit
      assert plan.participants["support-human"].while_present.record_audio == false

      for field <- [:capabilities, :while_present] do
        source = put_in(input, [:participants, "caller", field], %{})
        path = ["participants", "caller", Atom.to_string(field)]

        assert {:error, %Error{details: %{"path" => ^path}}} =
                 CallSpec.new(source, resource_id: "support", revision: 7)

        assert {:ok, _spec} =
                 CallSpec.new(Map.put(source, :schema_version, "20261004.01"),
                   resource_id: "support",
                   revision: 7
                 )
      end
    end
  end

  defp current_input do
    call_spec_input()
    |> Map.drop([:entry_caller, :entry_receiver])
    |> Map.merge(%{
      schema_version: "20261125.01",
      incoming_call: %{caller: "caller", handled_by: "reception"},
      opening_audio: %{type: "text", text: "Notice"}
    })
  end

  test "resolves the opening's explicit TTS selection with a human initial receiver" do
    input =
      call_spec_input()
      |> put_in([:participants, "reception"], %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "start_call"}
      })
      |> Map.put(:opening_audio, %{
        type: "text",
        text: "This call may be recorded.",
        text_to_speech: %{provider: "morse", model: "morse"}
      })

    assert {:ok, call_spec} = CallSpec.new(input, resource_id: "support", revision: 7)
    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation(), registries())
    assert plan.opening_audio.text_to_speech.provider == "morse"
    assert plan.opening_audio.text_to_speech.model == "morse"
    assert Map.fetch!(plan.participants, "reception").capabilities.text_to_speech == nil
  end

  test "text opening requires its own selection even when the agent has a default voice" do
    input =
      call_spec_input()
      |> put_in([:defaults, :capabilities, :text_to_speech], %{provider: "morse", model: "morse"})
      |> Map.put(:opening_audio, %{type: "text", text: "Notice"})

    assert {:error, %Error{details: %{"path" => ["opening_audio", "text_to_speech"]}}} =
             CallSpec.new(input, resource_id: "support", revision: 7)
  end

  test "rejects legacy, wrong-kind, and malformed opening selections without inheriting defaults" do
    for selection <- [
          "missing",
          "test-model",
          nil,
          "",
          false,
          %{provider: "fixture", model: "test"}
        ] do
      input =
        Map.put(call_spec_input(), :opening_audio, %{
          type: "text",
          text: "Notice",
          text_to_speech: selection
        })

      assert {:error, %Error{details: %{"path" => ["opening_audio", "text_to_speech"]}}} =
               CallSpec.new(input, resource_id: "support", revision: 7)
    end
  end

  test "pins supported text and HTTPS file sources into the resolved plan" do
    assert CallSpec.schema_version() == "20261125.01"

    for {input, expected} <- [
          {%{
             type: "text",
             text: "This call may be recorded.",
             text_to_speech: %{provider: "morse", model: "morse"}
           },
           %OpeningAudio{
             type: :text,
             text: "This call may be recorded.",
             url: nil,
             text_to_speech: %Vxpipe.CallEngine.CallSpec.CapabilitySelection{
               kind: :text_to_speech,
               provider: "morse",
               model: "morse",
               credential_name: nil,
               options: %{},
               provider_options: %{}
             }
           }},
          {%{type: "file_url", url: "https://assets.example.test/opening.wav"},
           %OpeningAudio{
             type: :file_url,
             text: nil,
             url: "https://assets.example.test/opening.wav"
           }}
        ] do
      assert {:ok, call_spec} =
               call_spec_input()
               |> Map.put(:opening_audio, input)
               |> CallSpec.new(resource_id: "support", revision: 7)

      assert call_spec.opening_audio == expected
      assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation(), registries())
      assert plan.opening_audio.type == expected.type
      assert plan.opening_audio.text == expected.text
      assert plan.opening_audio.url == expected.url
    end
  end

  test "omission adds no opening audio and malformed sources fail at their exact path" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 7)

    assert call_spec.opening_audio == nil

    for {opening_audio, path} <- [
          {%{type: "text", text: ""}, ["opening_audio", "text"]},
          {%{type: "text", text: "hello", url: "https://example.test/a.wav"},
           ["opening_audio", "url"]},
          {%{type: "file_url", url: "http://example.test/a.wav"}, ["opening_audio", "url"]},
          {%{type: "file_url", url: "https://user@example.test/a.wav"}, ["opening_audio", "url"]},
          {%{type: "file_url", url: "https://example.test/a.wav#part"}, ["opening_audio", "url"]},
          {%{
             type: "file_url",
             url: "https://example.test/a.wav",
             text_to_speech: %{provider: "morse", model: "morse"}
           }, ["opening_audio", "text_to_speech"]},
          {%{type: "unknown", text: "hello"}, ["opening_audio", "type"]}
        ] do
      assert {:error, %Error{code: :invalid_call_spec, details: %{"path" => ^path}}} =
               call_spec_input()
               |> Map.put(:opening_audio, opening_audio)
               |> CallSpec.new(resource_id: "support", revision: 7)
    end
  end

  defp call_spec_input do
    %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          prompt: "Answer clearly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp invocation do
    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "support", revision: 7},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    invocation
  end

  defp registries do
    %{
      host_tools: %{}
    }
  end
end
