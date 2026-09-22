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
    assert {:push_text, 2} in callbacks
    assert {:interrupt, 2} in callbacks
    assert {:send_tool_result, 3} in callbacks
    assert {:close, 1} in callbacks
  end

  test "morse STS configures a closed :sts descriptor" do
    assert {:ok, descriptor} = MorseSTS.configure([])
    assert descriptor.kind == :sts
    assert :ok = Descriptor.validate(descriptor)
  end

  test "STS descriptors admit the conversational activity and text-settlement vocabulary" do
    assert {:ok, descriptor} = MorseSTS.configure([])

    assert Event.supported?(%Event{kind: :speech_started}, descriptor)
    assert Event.supported?(%Event{kind: :transcript}, descriptor)

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
