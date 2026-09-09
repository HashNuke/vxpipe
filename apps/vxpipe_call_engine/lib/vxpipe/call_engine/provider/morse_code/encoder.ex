defmodule Vxpipe.CallEngine.Provider.MorseCode.Encoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.MorseCode.{Alphabet, Config}

  @type error ::
          :empty_text
          | :input_too_large
          | :invalid_text
          | :output_too_large
          | :unsupported_character

  @spec encode(Config.t(), String.t()) :: {:ok, binary()} | {:error, error()}
  def encode(%Config{} = config, text) when is_binary(text) do
    with :ok <- valid_text(text),
         :ok <- input_size(text, config),
         {:ok, words} <- normalize_words(text),
         {:ok, runs} <- encode_words(words),
         runs = runs ++ [{:silence, config.end_gap_units}],
         :ok <- output_size(runs, config) do
      {:ok, render(runs, config)}
    end
  end

  def encode(%Config{}, _text), do: {:error, :invalid_text}

  defp valid_text(text) do
    if String.valid?(text), do: :ok, else: {:error, :invalid_text}
  end

  defp input_size(text, config) do
    if byte_size(text) <= config.maximum_text_bytes,
      do: :ok,
      else: {:error, :input_too_large}
  end

  defp normalize_words(text) do
    words = text |> String.upcase() |> String.split()
    if words == [], do: {:error, :empty_text}, else: {:ok, words}
  end

  defp encode_words(words) do
    words
    |> Enum.reduce_while({:ok, []}, fn word, {:ok, encoded_words} ->
      case encode_word(word) do
        {:ok, runs} -> {:cont, {:ok, [runs | encoded_words]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded_words} ->
        runs = encoded_words |> Enum.reverse() |> Enum.intersperse([{:silence, 7}])
        {:ok, List.flatten(runs)}

      {:error, _reason} = error ->
        error
    end
  end

  defp encode_word(word) do
    word
    |> String.graphemes()
    |> Enum.reduce_while({:ok, []}, fn character, {:ok, encoded_characters} ->
      case Alphabet.encode(character) do
        {:ok, signal} -> {:cont, {:ok, [encode_signal(signal) | encoded_characters]}}
        {:error, _reason} -> {:halt, {:error, :unsupported_character}}
      end
    end)
    |> case do
      {:ok, encoded_characters} ->
        runs =
          encoded_characters
          |> Enum.reverse()
          |> Enum.intersperse([{:silence, 3}])
          |> List.flatten()

        {:ok, runs}

      {:error, _reason} = error ->
        error
    end
  end

  defp encode_signal(signal) do
    signal
    |> String.graphemes()
    |> Enum.map(fn
      "." -> {:tone, 1}
      "-" -> {:tone, 3}
    end)
    |> Enum.intersperse({:silence, 1})
  end

  defp output_size(runs, config) do
    total_units = Enum.reduce(runs, 0, fn {_kind, units}, total -> total + units end)
    bytes = total_units * unit_samples(config) * 2
    if bytes <= config.maximum_audio_bytes, do: :ok, else: {:error, :output_too_large}
  end

  defp render(runs, config) do
    runs
    |> Enum.map(fn
      {:tone, units} -> tone(units * unit_samples(config), config)
      {:silence, units} -> :binary.copy(<<0, 0>>, units * unit_samples(config))
    end)
    |> IO.iodata_to_binary()
  end

  defp tone(sample_count, config) do
    radians_per_sample = 2.0 * :math.pi() * config.frequency_hz / config.sample_rate

    for sample_index <- 0..(sample_count - 1), into: <<>> do
      sample = round(:math.sin(sample_index * radians_per_sample) * config.amplitude)
      <<sample::signed-little-16>>
    end
  end

  defp unit_samples(config),
    do: div(config.sample_rate * config.unit_duration_ms, 1_000)
end
