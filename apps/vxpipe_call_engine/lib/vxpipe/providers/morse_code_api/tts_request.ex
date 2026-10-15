defmodule Vxpipe.Providers.MorseCodeApi.TTSRequest do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.{PCMStream, SocketConnection}
  alias Vxpipe.Providers.MorseCodeApi.TTS

  def run(%TTS{} = config, text, consume) when is_function(consume, 1) do
    case perform(config, text, consume) do
      :ok -> :ok
      _failure -> {:error, :provider_unavailable}
    end
  rescue
    _error -> {:error, :provider_unavailable}
  catch
    _, _reason -> {:error, :provider_unavailable}
  end

  defp perform(config, text, consume) do
    with :ok <- TTS.validate_text(text),
         {:ok, connection, frames} <-
           SocketConnection.open(TTS.connection_options(config), receive_timeout: 10_000) do
      # The supervised request task owns the TCP/TLS socket. Killing the task
      # during cancellation closes the socket even when it is waiting for credit.
      try do
        with {:ok, connection} <- send_input(connection, text) do
          deadline = System.monotonic_time(:millisecond) + 60_000
          process_frames(connection, frames, PCMStream.new(), consume, deadline)
        end
      after
        SocketConnection.close(connection)
      end
    end
  end

  defp send_input(connection, text) do
    Enum.reduce_while([" ", text, ""], {:ok, connection}, fn input, {:ok, connection} ->
      case SocketConnection.send_frame(connection, {:text, JSON.encode!(%{text: input})}) do
        {:ok, connection} -> {:cont, {:ok, connection}}
        failure -> {:halt, failure}
      end
    end)
  end

  defp process_frames(connection, [], pcm, consume, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      message ->
        with {:ok, connection, frames} <- SocketConnection.receive_frames(connection, message) do
          process_frames(connection, frames, pcm, consume, deadline)
        end
    after
      remaining -> {:error, :timeout}
    end
  end

  defp process_frames(connection, [{:text, payload} | rest], pcm, consume, deadline) do
    case TTS.decode(payload) do
      {:ok, audio} ->
        with {:ok, pcm, chunks} <- PCMStream.feed(pcm, audio),
             :ok <- consume_chunks(chunks, consume) do
          process_frames(connection, rest, pcm, consume, deadline)
        end

      :completed ->
        PCMStream.finish(pcm)

      _invalid ->
        {:error, :invalid_message}
    end
  end

  defp process_frames(connection, [{:ping, data} | rest], pcm, consume, deadline) do
    with {:ok, connection} <- SocketConnection.send_frame(connection, {:pong, data}),
         do: process_frames(connection, rest, pcm, consume, deadline)
  end

  defp process_frames(connection, [{:pong, _data} | rest], pcm, consume, deadline),
    do: process_frames(connection, rest, pcm, consume, deadline)

  defp process_frames(_connection, _frames, _pcm, _consume, _deadline),
    do: {:error, :incomplete_stream}

  defp consume_chunks(chunks, consume) do
    Enum.reduce_while(chunks, :ok, fn chunk, :ok ->
      case consume.(chunk) do
        :ok -> {:cont, :ok}
        _failure -> {:halt, {:error, :consumer_unavailable}}
      end
    end)
  end
end
