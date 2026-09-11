defmodule Vxpipe.Gateway.Telephony.Twilio.PlaybackClearerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.Twilio.PlaybackClearer

  test "sends the exact clear command for the pinned stream" do
    assert :ok =
             PlaybackClearer.clear(
               socket_owner: self(),
               stream_id: "MZ00000000000000000000000000000000"
             )

    assert_receive {:vxpipe_twilio_socket_send, message}

    assert JSON.decode!(message) == %{
             "event" => "clear",
             "streamSid" => "MZ00000000000000000000000000000000"
           }
  end

  test "rejects an incomplete playback target without sending a command" do
    assert {:error, :invalid_playback_target} = PlaybackClearer.clear(socket_owner: self())
    refute_receive {:vxpipe_twilio_socket_send, _message}
  end
end
