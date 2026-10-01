defmodule Vxpipe.Providers.ElevenLabs.ScribeVADSocketTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.ScribeSocket

  test "socket delivers the requested VAD acknowledgement and rejects a manual-mode mismatch" do
    state = %{owner: self(), commit_strategy: :vad}

    ready = %{
      "message_type" => "session_started",
      "session_id" => "session-scribe-vad",
      "config" => %{"commit_strategy" => "vad"}
    }

    assert {:ok, ^state} = ScribeSocket.handle_frame({:text, JSON.encode!(ready)}, state)
    observer = self()
    assert_receive {:vxpipe_scribe_transport, ^observer, {:event, {:ready, "session-scribe-vad"}}}

    mismatch = put_in(ready, ["config", "commit_strategy"], "manual")
    assert {:ok, ^state} = ScribeSocket.handle_frame({:text, JSON.encode!(mismatch)}, state)
    assert_receive {:vxpipe_scribe_transport, ^observer, {:closed, :invalid_message}}
  end

  test "unknown commit strategies reject socket startup before a connection is attempted" do
    assert {:error, :invalid_configuration} =
             ScribeSocket.start_link(owner: self(), commit_strategy: :invented)
  end
end
