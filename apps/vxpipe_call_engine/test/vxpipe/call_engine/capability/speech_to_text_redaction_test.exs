defmodule Vxpipe.CallEngine.Capability.SpeechToTextRedactionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.SpeechToText.State

  test "routine state inspection does not print reconnect credentials or transport options" do
    state =
      struct(State,
        connection: %{
          url: "wss://example.test",
          headers: [{"Authorization", "private-credential-marker"}]
        },
        transport_options: [token: "private-transport-marker"],
        identity: %{participant_id: "participant"},
        provider_module: Vxpipe.CallEngine.Provider.Deepgram.Flux,
        readiness_status: :ready
      )

    refute inspect(state) =~ "private-credential-marker"
    refute inspect(state) =~ "private-transport-marker"
    assert inspect(state) =~ "readiness_status: :ready"
  end
end
