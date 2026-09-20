defmodule Vxpipe.CallEngine.Capability.TextToSpeech.OutputTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.TextToSpeech.Output
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TextToSpeechRequest

  test "an unanswered finish fails within the output request deadline" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    :ok = TestAudioOutputSink.defer_finish(sink, true)
    output = start_supervised!({Output, request_timeout: 10})
    request_ref = make_ref()
    request = request(sink)

    assert :ok = Output.finish(output, self(), request_ref, request)
    assert_receive {:test_audio_output_finish, ^sink, "turn-output-timeout"}

    assert_receive {:vxpipe_tts_output, ^output, ^request_ref,
                    {:finish, {:error, :sink_unavailable}}},
                   100

    :ok = TestAudioOutputSink.complete_finish(sink)
    refute_receive {:vxpipe_tts_output, ^output, ^request_ref, _late_result}
  end

  defp request(sink) do
    %TextToSpeechRequest{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-test",
      source_participant_id: "human-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: "turn-output-timeout",
      output_id: "output-test",
      text: "E",
      output_sink: sink
    }
  end
end
