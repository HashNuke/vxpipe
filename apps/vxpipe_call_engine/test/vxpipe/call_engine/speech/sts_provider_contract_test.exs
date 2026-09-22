defmodule Vxpipe.CallEngine.Speech.STSProviderContractTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{Descriptor, Event, STSProvider}
  alias Vxpipe.Providers.Registry

  test "STSProvider declares the bounded conversational callback set" do
    callbacks = STSProvider.behaviour_info(:callbacks)

    assert {:configure, 1} in callbacks
    assert {:start_link, 1} in callbacks
    assert {:push_audio, 2} in callbacks
    assert {:push_text, 3} in callbacks
    assert {:input_activity, 2} in callbacks
    assert {:interrupt, 2} in callbacks
    assert {:send_tool_result, 3} in callbacks
    assert {:close, 1} in callbacks
  end

  test "STS descriptors carry the admission facts the room decides on" do
    assert {:ok, descriptor} = MorseSTS.configure([])

    assert descriptor.turn_control == "provider"
    assert descriptor.turn_control_supported == ["provider", "external", "hybrid"]
    assert descriptor.input_transcript?
    assert descriptor.output_transcript?
    assert descriptor.output_settlement == :transcript_end
    assert is_boolean(descriptor.history_reconciliation?)
  end

  test "STS descriptors reject missing transcript and turn-control facts" do
    base = [
      kind: :sts,
      settings: %{},
      format: %{
        encoding: :linear16,
        container: :raw,
        sample_rate: 16_000,
        channels: 1,
        byte_order: :little,
        signed?: true
      },
      usage_identity: %{provider: :probe, model: :probe, provenance: :locally_measured},
      readiness: :initialized,
      endpointing: :provider_gap,
      speech_start?: true,
      turn_control: "provider",
      turn_control_supported: ["provider", "external", "hybrid"],
      input_transcript?: true,
      output_transcript?: true,
      output_settlement: :transcript_end,
      history_reconciliation?: false
    ]

    assert {:ok, _} = Descriptor.new(base)

    for override <- [
          [turn_control: nil],
          [turn_control: "automatic"],
          [turn_control: "external", turn_control_supported: ["provider"]],
          [turn_control_supported: []],
          [output_settlement: nil],
          [output_settlement: :audio_end],
          [endpointing: :none],
          [endpointing: :provider_gap, speech_start?: false]
        ] do
      fields = Keyword.merge(base, override)
      assert {:error, :invalid_descriptor} = Descriptor.new(fields), inspect(override)
    end

    assert {:ok, external} =
             Descriptor.new(
               Keyword.merge(base,
                 turn_control: "external",
                 endpointing: :external,
                 speech_start?: false
               )
             )

    assert external.turn_control == "external"
  end

  test "morse STS descriptor honours transcript options" do
    assert {:ok, no_output} = MorseSTS.configure(output_transcript: false)
    refute no_output.output_transcript?
    assert no_output.input_transcript?
  end

  test "STS descriptors admit the conversational activity and text-settlement vocabulary" do
    assert {:ok, descriptor} = MorseSTS.configure([])

    assert Event.supported?(%Event{kind: :speech_started}, descriptor)
    refute Event.supported?(%Event{kind: :transcript}, descriptor)
    assert Event.supported?(%Event{kind: :output_completed}, descriptor)

    assert Event.supported?(
             %Event{kind: :turn_ended, endpointing: :provider_gap},
             descriptor
           )

    refute Event.supported?(
             %Event{kind: :turn_ended, endpointing: :provider_semantic},
             descriptor
           )

    refute Event.supported?(%Event{kind: :completed}, descriptor)
  end

  test "STS transcript direction is explicit and gated by descriptor coverage" do
    assert {:ok, with_text} = MorseSTS.configure([])
    assert {:ok, without_output} = MorseSTS.configure(output_transcript: false)

    turn = make_ref()

    assert Event.supported?(%Event{kind: :input_transcript}, with_text)
    assert Event.supported?(%Event{kind: :output_transcript}, with_text)
    refute Event.supported?(%Event{kind: :output_transcript}, without_output)
    assert Event.supported?(%Event{kind: :input_transcript}, without_output)

    assert {:ok, %Event{kind: :input_transcript, turn_ref: ^turn}} =
             Event.build(:input_transcript, turn_ref: turn, text: "hello")

    assert {:ok, %Event{kind: :output_transcript, turn_ref: ^turn}} =
             Event.build(:output_transcript, turn_ref: turn, text: "hi")

    assert {:error, :invalid_event} =
             Event.build(:output_transcript, turn_ref: turn, text: <<0xFF>>)

    assert {:error, :invalid_event} = Event.build(:input_transcript, text: "no turn")
  end

  test "STS tool and interruption vocabulary is closed and attributed" do
    assert {:ok, descriptor} = MorseSTS.configure([])
    call = make_ref()
    turn = make_ref()

    assert Event.supported?(%Event{kind: :tool_call}, descriptor)
    assert Event.supported?(%Event{kind: :tool_cancelled}, descriptor)
    assert Event.supported?(%Event{kind: :interrupted}, descriptor)

    refute Event.supported?(%Event{kind: :tool_call}, %{
             descriptor
             | kind: :stt
           })

    assert {:ok, %Event{kind: :tool_call, call_ref: ^call}} =
             Event.build(:tool_call,
               call_ref: call,
               turn_ref: turn,
               tool_name: "lookup_order",
               arguments: %{"order_id" => "123"}
             )

    assert {:ok, %Event{kind: :tool_cancelled, call_ref: ^call}} =
             Event.build(:tool_cancelled, call_ref: call)

    assert {:ok, %Event{kind: :interrupted, turn_ref: ^turn}} =
             Event.build(:interrupted, turn_ref: turn)

    assert {:error, :invalid_event} = Event.build(:tool_call, call_ref: call, tool_name: "")
    assert {:error, :invalid_event} = Event.build(:interrupted, [])
  end

  test "STS text admission carries its own submission evidence" do
    assert {:ok, descriptor} = MorseSTS.configure([])
    ref = make_ref()

    assert Event.supported?(
             %Event{kind: :input_submitted, provenance: :locally_measured},
             descriptor
           )

    assert {:ok, %Event{kind: :input_submitted, request_ref: ^ref}} =
             Event.build(:input_submitted, request_ref: ref, provenance: :locally_measured)
  end

  test "unsupported STS providers fail closed without fallback" do
    selection = %CapabilitySelection{
      kind: :speech_to_speech,
      provider: "deepgram",
      model: "morse",
      credential_name: nil,
      options: %{},
      provider_options: %{}
    }

    assert {:error, :unsupported_capability} = CapabilityCatalog.validate(selection)
    assert {:error, :unsupported_provider_capability} = Registry.fetch_capability("google", :sts)
  end

  test ":sts adapter resolution is manifest-gated with no fallback" do
    for provider <- ["google", "deepgram", "rime"] do
      selection = %CapabilitySelection{
        kind: :speech_to_speech,
        provider: provider,
        model: "morse",
        credential_name: nil,
        options: %{},
        provider_options: %{}
      }

      assert {:error, :unsupported_provider_capability} = CapabilityCatalog.adapter(selection)
    end
  end
end
