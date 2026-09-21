defmodule Vxpipe.Providers.Google.TTSStream do
  @moduledoc false

  @maximum_frame_bytes 1_400_000
  @maximum_audio_chunk_bytes 131_072
  @maximum_audio_bytes 33_554_432

  @derive {Inspect, only: [:completed?, :audio_bytes]}
  defstruct buffer: "", completed?: false, audio_bytes: 0

  def new, do: %__MODULE__{}

  def feed(%__MODULE__{} = state, chunk) when is_binary(chunk) do
    buffer = String.replace(state.buffer <> chunk, "\r\n", "\n")
    frames = String.split(buffer, "\n\n")
    pending = List.last(frames)

    if byte_size(pending) > @maximum_frame_bytes do
      {:error, :invalid_stream}
    else
      frames
      |> Enum.drop(-1)
      |> Enum.reduce_while({:ok, %{state | buffer: pending}, []}, fn frame,
                                                                     {:ok, state, events} ->
        case parse_frame(state, frame) do
          {:ok, state, next} -> {:cont, {:ok, state, events ++ next}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  def feed(_state, _chunk), do: {:error, :invalid_stream}

  def finish(%__MODULE__{completed?: true, buffer: buffer}) when buffer in ["", "\n"], do: :ok
  def finish(%__MODULE__{}), do: {:error, :incomplete_stream}

  defp parse_frame(state, frame) when byte_size(frame) <= @maximum_frame_bytes do
    data =
      frame
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&String.trim_leading(&1, "data: "))
      |> Enum.join("\n")

    case data do
      "" -> {:ok, state, []}
      "[DONE]" -> {:ok, state, []}
      _other -> parse_data(state, data)
    end
  end

  defp parse_frame(_state, _frame), do: {:error, :invalid_stream}

  defp parse_data(state, data) do
    case JSON.decode(data) do
      {:ok, %{"event_type" => "step.delta", "delta" => %{"type" => "audio"} = delta}} ->
        parse_audio(state, delta)

      {:ok,
       %{"event_type" => "interaction.completed", "interaction" => %{"status" => "completed"}}} ->
        {:ok, %{state | completed?: true}, [:completed]}

      {:ok, %{"event_type" => kind}} when kind in ["interaction.failed", "error"] ->
        {:error, :provider_failure}

      {:ok, %{"event_type" => _other}} ->
        {:ok, state, []}

      _invalid ->
        {:error, :invalid_stream}
    end
  end

  defp parse_audio(%__MODULE__{completed?: false} = state, %{
         "mime_type" => "audio/l16",
         "data" => encoded
       })
       when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, audio}
      when byte_size(audio) > 0 and byte_size(audio) <= @maximum_audio_chunk_bytes and
             rem(byte_size(audio), 2) == 0 and
             state.audio_bytes + byte_size(audio) <= @maximum_audio_bytes ->
        {:ok, %{state | audio_bytes: state.audio_bytes + byte_size(audio)}, [{:audio, audio}]}

      _invalid ->
        {:error, :invalid_stream}
    end
  end

  defp parse_audio(_state, _delta), do: {:error, :invalid_stream}
end
