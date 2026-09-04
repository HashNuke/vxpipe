defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxSocketTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.Deepgram.FluxSocket

  test "forwards provider text and binary frames to the capability owner" do
    state = %{owner: self()}

    assert {:ok, ^state} = FluxSocket.handle_frame({:text, "text-message"}, state)
    assert_receive {:vxpipe_stt_transport, socket, {:message, "text-message"}}
    assert socket == self()

    assert {:ok, ^state} = FluxSocket.handle_frame({:binary, "binary-message"}, state)
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "binary-message"}}
  end

  test "reports a bounded transport failure and does not request reconnection" do
    state = %{owner: self()}

    assert {:ok, ^state} =
             FluxSocket.handle_disconnect(%{reason: {:error, "provider detail"}}, state)

    assert_receive {:vxpipe_stt_transport, socket, {:closed, :connection_lost}}
    assert socket == self()
  end
end
