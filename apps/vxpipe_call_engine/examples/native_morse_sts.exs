defmodule Vxpipe.CallEngine.Examples.NativeMorseSTS do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}

  @chunk_size 320
  @sample_rate 16_000
  @channels 1
  @bits_per_sample 16

  def run([text, output_path]) do
    {:ok, tree} = CapabilityTree.start_link(owner: self())

    try do
      {:ok, allocation, :starting} =
        Session.start(CapabilityTree.scope(tree), provider: MorseSession, options: [], private: [])

      ready = receive_event(allocation, :ready)
      :ok = Session.ack(allocation, ready)

      {:ok, config} = Config.new([])
      {:ok, pcm} = Encoder.encode(config, text)
      push_chunks(allocation, pcm)

      started = receive_event(allocation, :speech_started)
      :ok = Session.ack(allocation, started)

      input_text = drain_until_turn_ended(allocation, nil)
      ended = receive_event(allocation, :turn_ended)
      :ok = Session.ack(allocation, ended)

      {:ok, output} = Session.admit_output(allocation, ended.turn_ref)
      {reply_text, reply_pcm} = drain_output(allocation, output, nil, [])

      :ok = Session.settle_output(allocation, output, 0)
      :ok = Session.close(allocation)

      :ok = File.mkdir_p(Path.dirname(output_path))
      :ok = File.write(output_path, wave(reply_pcm))

      IO.puts("input transcript: #{input_text}")
      IO.puts("reply transcript: #{reply_text}")
      IO.puts("wrote #{output_path}: #{byte_size(reply_pcm)} PCM bytes")
    after
      Supervisor.stop(tree)
    end
  end

  def run(_arguments) do
    raise ArgumentError,
          "usage: MIX_ENV=test mix run examples/native_morse_sts.exs TEXT OUTPUT.wav"
  end

  defp push_chunks(allocation, pcm) do
    for <<chunk::binary-size(@chunk_size) <- pcm>>, do: :ok = Session.push_audio(allocation, chunk)

    remainder = rem(byte_size(pcm), @chunk_size)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      :ok = Session.push_audio(allocation, tail)
    end
  end

  defp drain_until_turn_ended(allocation, last) do
    receive do
      {:vxpipe_speech, %Event{session: ^allocation, kind: :input_transcript, text: text} = event} ->
        :ok = Session.ack(allocation, event)
        drain_until_turn_ended(allocation, text)

      {:vxpipe_speech, %Event{session: ^allocation, kind: :turn_ended} = event} ->
        send(self(), {:vxpipe_speech, event})
        last
    after
      5_000 -> raise "turn end timed out"
    end
  end

  defp drain_output(allocation, output, text, chunks) do
    receive do
      {:vxpipe_speech, %Event{session: ^allocation, kind: :output_transcript, text: reply} = event} ->
        :ok = Session.ack(allocation, event)
        drain_output(allocation, output, reply, chunks)

      {:vxpipe_speech_audio, %Audio{session: ^allocation} = audio} ->
        :ok = Session.validate_audio(allocation, audio)
        :ok = Session.ack_audio(allocation, audio)
        drain_output(allocation, output, text, [audio.payload | chunks])

      {:vxpipe_speech, %Event{session: ^allocation, kind: :output_completed} = event} ->
        :ok = Session.ack(allocation, event)
        {text, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
    after
      5_000 -> raise "output timed out"
    end
  end

  defp receive_event(allocation, kind) do
    receive do
      {:vxpipe_speech, %Event{session: ^allocation, kind: ^kind} = event} -> event
    after
      5_000 -> raise "#{kind} event timed out"
    end
  end

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

Vxpipe.CallEngine.Examples.NativeMorseSTS.run(System.argv())
