defmodule Vxpipe.CallEngine.LiveTTSCancellation do
  @moduledoc false
  import ExUnit.Assertions
  alias Vxpipe.CallEngine.Speech.{Audio, Event, Session}

  def check(session) do
    assert {:ok, %{ref: request}} =
             Session.speak(
               session,
               "This phrase will be interrupted after its first audio chunk."
             )

    deadline = System.monotonic_time(:millisecond) + 15_000
    await_audio(session, request, deadline)
    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)
    await_cancelled(session, request, System.monotonic_time(:millisecond) + 10_000)
  end

  defp await_audio(session, request, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "interrupted utterance produced no audio before its deadline"

    receive do
      {:vxpipe_speech_audio, %Audio{session: ^session, request_ref: ^request} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        # Leave credit outstanding to exercise cancellation during delivery.
        :ok

      {:vxpipe_speech, %Event{session: ^session, kind: :input_submitted} = event} ->
        assert :ok = Session.ack(session, event)
        await_audio(session, request, deadline)

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("provider closed before interruption")
    after
      remaining -> flunk("interrupted utterance produced no audio")
    end
  end

  defp await_cancelled(session, request, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "provider did not settle cancellation before its deadline"

    receive do
      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request, kind: :cancelled} = event} ->
        assert :ok = Session.ack(session, event)

      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request, kind: :completed}} ->
        flunk("cancelled utterance was reported as completed")

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("cancellation closed the persistent provider session")
    after
      remaining -> flunk("provider did not settle cancellation")
    end
  end
end
