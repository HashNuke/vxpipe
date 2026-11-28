defmodule Vxpipe.Providers.DecisionsManifestTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Registry

  test "openai, google and jev advertise private decisions adapters" do
    assert {:ok, Vxpipe.Providers.OpenAI.Decisions} =
             Registry.fetch_capability("openai", :decisions)

    assert {:ok, Vxpipe.Providers.Google.Decisions} =
             Registry.fetch_capability("google", :decisions)

    assert {:ok, Vxpipe.Providers.Jev.Decisions} =
             Registry.fetch_capability("jev", :decisions)
  end

  test "unknown providers and unrelated capabilities never select a decisions fallback" do
    assert {:error, :unsupported_provider} = Registry.fetch_capability("unknown", :decisions)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("deepgram", :decisions)

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("telnyx", :decisions)
  end
end
