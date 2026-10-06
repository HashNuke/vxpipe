defmodule Vxpipe.Gateway.PhoneHandoffAssertionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.Gateway.PhoneHandoffAssertions

  test "recovery drains an earlier streaming acknowledgement fragment before the recovery request" do
    voice =
      start_supervised!(
        {TestTextToSpeechTransport,
         owner: self(), connection: [], transport_options: [observer: self()]}
      )

    owner = self()

    helper =
      start_supervised!(
        {Task,
         fn ->
           result =
             PhoneHandoffAssertions.await_recovery_speech(
               voice,
               System.monotonic_time(:millisecond) + 2_000
             )

           send(owner, {:recovery_wait_finished, result})
         end}
      )

    send(helper, {:test_tts_control, voice, JSON.encode!(%{type: "Speak", text: "Connecting "})})
    assert_receive {:vxpipe_tts_transport, ^voice, {:control, started}}, 500
    assert JSON.decode!(started)["type"] == "SpeechStarted"
    assert_receive {:vxpipe_tts_transport, ^voice, {:audio, _reference, audio}}, 500
    assert byte_size(audio) > 0
    assert_receive {:vxpipe_tts_transport, ^voice, {:control, completed}}, 500
    assert JSON.decode!(completed)["type"] == "SpeechMetadata"

    send(
      helper,
      {:test_tts_control, voice, JSON.encode!(%{type: "Speak", text: "We can continue."})}
    )

    assert_receive {:recovery_wait_finished, :ok}, 500
  end
end
