defmodule Vxpipe.CallEngine.CallSpec.STTVADSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  @path ["defaults", "capabilities", "speech_to_text"]

  test "caller STT defaults to false and accepts booleans independently of upstream options" do
    for input <- selections() do
      assert {:ok, omitted} = CapabilitySelection.new(input, :speech_to_text, @path)
      refute CapabilitySelection.vad?(omitted)

      for enabled <- [false, true] do
        assert {:ok, configured} =
                 CapabilitySelection.new(Map.put(input, :vad, enabled), :speech_to_text, @path)

        assert CapabilitySelection.vad?(configured) == enabled
        assert {:ok, options} = CapabilityCatalog.speech_options(configured)
        refute Keyword.has_key?(options, :vad)
        assert {:ok, provider} = CapabilityCatalog.adapter(configured)

        assert {:ok, descriptor} =
                 Vxpipe.CallEngine.Speech.ConversationalSTT.configure(
                   provider: provider,
                   options: options,
                   vad: enabled
                 )

        assert descriptor.settings.vad == enabled

        assert descriptor.speech_start_evidence ==
                 if(enabled, do: :local_acoustic, else: :transcript)
      end
    end
  end

  test "invalid values and other capabilities reject vad at its field path" do
    input = %{provider: "morse", model: "morse"}

    for value <- [nil, "false", 0, %{}, []] do
      assert {:error, error} =
               CapabilitySelection.new(Map.put(input, :vad, value), :speech_to_text, @path)

      assert error.details["path"] == @path ++ ["vad"]
    end

    for kind <- [:output_speech_to_text, :text_to_speech, :speech_to_speech, :model_inference],
        value <- [false, true] do
      assert {:error, error} =
               CapabilitySelection.new(Map.put(input, :vad, value), kind, [Atom.to_string(kind)])

      assert error.details["path"] == [Atom.to_string(kind), "vad"]
    end
  end

  test "false preserves old pinned selection identity and true changes it" do
    input = %{provider: "morse", model: "morse"}
    assert {:ok, omitted} = CapabilitySelection.new(input, :speech_to_text, @path)

    assert {:ok, disabled} =
             CapabilitySelection.new(Map.put(input, :vad, false), :speech_to_text, @path)

    assert {:ok, enabled} =
             CapabilitySelection.new(Map.put(input, :vad, true), :speech_to_text, @path)

    historical = Map.delete(omitted, :vad)

    expected =
      :crypto.hash(:sha256, :erlang.term_to_binary({"tenant", historical}, [:deterministic]))
      |> Base.encode16(case: :lower)

    assert CapabilitySelection.identity(omitted, "tenant") == expected
    assert CapabilitySelection.identity(disabled, "tenant") == expected
    assert CapabilitySelection.identity(enabled, "tenant") != expected
    assert :ok = CapabilitySelection.validate(historical, @path)
    refute CapabilitySelection.vad?(historical)
  end

  defp selections do
    [
      %{
        provider: "deepgram",
        model: "flux-general-en",
        options: %{encoding: "linear16", sample_rate: 48_000}
      },
      %{provider: "google", model: "gemini-3.5-transcribe-live"},
      %{provider: "cartesia", model: "ink-2"},
      %{provider: "elevenlabs", model: "scribe_v2_realtime"},
      %{provider: "morse", model: "morse"}
    ]
  end
end
