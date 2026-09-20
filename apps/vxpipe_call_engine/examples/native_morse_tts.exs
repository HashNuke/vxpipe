defmodule Vxpipe.CallEngine.Examples.NativeMorseTTS do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}

  @sample_rate 16_000
  @channels 1
  @bits_per_sample 16

  def run([text, output_path]) do
    {:ok, tree} = CapabilityTree.start_link(owner: self())

    try do
      {:ok, allocation, :starting} =
        Session.start(CapabilityTree.scope(tree),
          provider: MorseSession,
          options: [
            sample_rate: @sample_rate,
            unit_duration_ms: 60,
            amplitude: 2_048
          ],
          private: [emit_interval_ms: 0]
        )

      ready = receive_event(allocation, :ready)
      :ok = Session.ack(allocation, ready)
      {:ok, descriptor} = Session.describe(allocation)
      assert_format!(descriptor.format)
      {:ok, request} = Session.speak(allocation, text)
      pcm = drain(allocation, request.ref, [])
      :ok = File.mkdir_p(Path.dirname(output_path))
      :ok = File.write(output_path, wave(pcm))
      :ok = Session.close(allocation)

      duration_ms = div(byte_size(pcm) * 1_000, @sample_rate * @channels * 2)

      IO.puts(
        "wrote #{output_path}: #{byte_size(pcm)} PCM bytes, #{duration_ms} ms, " <>
          "#{@sample_rate} Hz mono signed little-endian PCM16"
      )
    after
      Supervisor.stop(tree)
    end
  end

  def run(_arguments) do
    raise ArgumentError,
          "usage: MIX_ENV=test mix run examples/native_morse_tts.exs TEXT OUTPUT.wav"
  end

  defp drain(allocation, request_ref, chunks) do
    receive do
      {:vxpipe_speech, %Event{session: ^allocation, kind: :input_submitted} = event} ->
        :ok = Session.ack(allocation, event)
        true = event.request_ref == request_ref
        drain(allocation, request_ref, chunks)

      {:vxpipe_speech_audio, %Audio{session: ^allocation} = audio} ->
        :ok = Session.validate_audio(allocation, audio)
        true = audio.request_ref == request_ref
        chunks = [audio.payload | chunks]
        :ok = Session.ack_audio(allocation, audio)
        drain(allocation, request_ref, chunks)

      {:vxpipe_speech, %Event{session: ^allocation, kind: :completed} = event} ->
        :ok = Session.ack(allocation, event)
        true = event.request_ref == request_ref
        chunks |> Enum.reverse() |> IO.iodata_to_binary()

      {:vxpipe_speech, %Event{session: ^allocation, kind: :failed} = event} ->
        :ok = Session.ack(allocation, event)
        true = event.request_ref == request_ref
        raise "synthesis failed: #{event.reason}"
    after
      5_000 -> raise "synthesis timed out"
    end
  end

  defp receive_event(allocation, kind) do
    receive do
      {:vxpipe_speech, %Event{session: ^allocation, kind: ^kind} = event} -> event
    after
      5_000 -> raise "#{kind} event timed out"
    end
  end

  defp assert_format!(%{
         encoding: :linear16,
         container: :raw,
         sample_rate: @sample_rate,
         channels: @channels,
         byte_order: :little,
         signed?: true
       }),
       do: :ok

  defp assert_format!(format), do: raise("unexpected output format: #{inspect(format)}")

  defp wave(pcm) do
    block_align = div(@channels * @bits_per_sample, 8)
    byte_rate = @sample_rate * block_align

    format =
      <<1::little-16, @channels::little-16, @sample_rate::little-32, byte_rate::little-32,
        block_align::little-16, @bits_per_sample::little-16>>

    body = "fmt " <> <<byte_size(format)::little-32>> <> format
    body = body <> "data" <> <<byte_size(pcm)::little-32>> <> pcm
    "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
  end
end

Vxpipe.CallEngine.Examples.NativeMorseTTS.run(System.argv())
