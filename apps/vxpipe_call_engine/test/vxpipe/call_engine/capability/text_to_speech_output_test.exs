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

  test "stop receipt is timestamped only after the sink acknowledges interruption" do
    parent = self()

    sink =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:"$gen_call", from, {:vxpipe_audio_output_interrupt, _, _}} ->
               send(parent, {:stop_requested, self()})

               receive do
                 :acknowledge -> GenServer.reply(from, {:ok, 25})
               end
           end
         end}
      )

    output = start_supervised!(Output)

    caller =
      start_supervised!(
        Supervisor.child_spec(
          {Task,
           fn ->
             result = Output.interrupt_with_receipt(output, make_ref(), request(sink), parent)
             send(parent, {:stop_receipt, result})
           end},
          id: :receipt_caller
        )
      )

    assert is_pid(caller)
    assert_receive {:stop_requested, ^sink}
    refute_receive {:stop_receipt, _}, 0
    acknowledged_after = System.monotonic_time(:microsecond)
    send(sink, :acknowledge)
    assert_receive {:stop_receipt, {:ok, 25, received_at}}
    assert received_at >= acknowledged_after
    assert received_at <= System.monotonic_time(:microsecond)
  end

  test "missing acknowledgement returns no receipt and a late reply cannot create one" do
    parent = self()

    sink =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:"$gen_call", from, {:vxpipe_audio_output_interrupt, _, _}} ->
               send(parent, {:stop_requested, self()})

               receive do
                 :acknowledge ->
                   GenServer.reply(from, {:ok, 25})
                   send(parent, :late_acknowledgement_sent)
               end
           end
         end}
      )

    output = start_supervised!({Output, request_timeout: 10})

    start_supervised!(
      Supervisor.child_spec(
        {Task,
         fn ->
           send(
             parent,
             {:stop_receipt,
              Output.interrupt_with_receipt(output, make_ref(), request(sink), parent)}
           )
         end},
        id: :receipt_caller
      )
    )

    assert_receive {:stop_requested, ^sink}
    assert_receive {:stop_receipt, {:error, :sink_unavailable}}
    send(sink, :acknowledge)
    assert_receive :late_acknowledgement_sent
    _ = :sys.get_state(output)
    refute_received {:stop_receipt, _}
  end

  test "a rejected interruption has no stop receipt" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    output = start_supervised!(Output)

    assert {:error, :wrong_turn} =
             Output.interrupt_with_receipt(output, make_ref(), request(sink), self())
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
