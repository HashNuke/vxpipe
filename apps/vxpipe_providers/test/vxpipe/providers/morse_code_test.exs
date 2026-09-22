defmodule Vxpipe.Providers.MorseCodeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Registry

  test "morse is a credential-free local provider namespace for stt/tts/sts" do
    assert {:ok, Vxpipe.Providers.MorseCode} = Registry.fetch("morse")

    assert {:ok, Vxpipe.Providers.MorseCode.STTSession} =
             Registry.fetch_capability("morse", :stt)

    assert {:ok, Vxpipe.Providers.MorseCode.TTSSession} =
             Registry.fetch_capability("morse", :tts)

    assert {:ok, Vxpipe.Providers.MorseCode.STSSession} =
             Registry.fetch_capability("morse", :sts)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("morse", :credential)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("morse", :telephony)
  end
end
