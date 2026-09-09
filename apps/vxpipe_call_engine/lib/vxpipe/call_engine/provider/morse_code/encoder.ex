defmodule Vxpipe.CallEngine.Provider.MorseCode.Encoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.MorseCode.{Alphabet, Config}

  @render_chunk_samples 4_096

  @enforce_keys [:config, :runs]
  defstruct @enforce_keys ++
              [current_kind: nil, current_remaining_samples: 0, tone_sample_index: 0]

  @type error ::
          :empty_text
          | :input_too_large
          | :invalid_text
          | :output_too_large
          | :unsupported_character

  @type t :: %__MODULE__{
          config: Config.t(),
          runs: [{:tone | :silence, pos_integer()}],
          current_kind: :tone | :silence | nil,
          current_remaining_samples: non_neg_integer(),
          tone_sample_index: non_neg_integer()
        }

  @spec encode(Config.t(), String.t()) :: {:ok, binary()} | {:error, error()}
  def encode(%Config{} = config, text) when is_binary(text) do
    with {:ok, encoder} <- start(config, text) do
      {:ok, drain(encoder, [])}
    end
  end

  def encode(%Config{}, _text), do: {:error, :invalid_text}

  @spec start(Config.t(), String.t()) :: {:ok, t()} | {:error, error()}
  def start(%Config{} = config, text) when is_binary(text) do
    with :ok <- valid_text(text),
         :ok <- input_size(text, config),
         {:ok, words} <- normalize_words(text),
         {:ok, runs} <- encode_words(words),
         runs = runs ++ [{:silence, config.end_gap_units}],
         :ok <- output_size(runs, config) do
      {:ok, %__MODULE__{config: config, runs: runs}}
    end
  end

  def start(%Config{}, _text), do: {:error, :invalid_text}

  @spec next(t(), pos_integer()) :: {:ok, binary(), t()} | :done | {:error, :invalid_chunk_size}
  def next(%__MODULE__{} = encoder, maximum_samples)
      when is_integer(maximum_samples) and maximum_samples > 0 do
    take_samples(load_run(encoder), maximum_samples, [])
  end

  def next(%__MODULE__{}, _maximum_samples), do: {:error, :invalid_chunk_size}

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

  defp drain(encoder, chunks) do
    case next(encoder, @render_chunk_samples) do
      {:ok, chunk, encoder} -> drain(encoder, [chunk | chunks])
      :done -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp take_samples(
         %__MODULE__{current_kind: nil, runs: []},
         _remaining_samples,
         []
       ),
       do: :done

  defp take_samples(
         %__MODULE__{current_kind: nil, runs: []} = encoder,
         _remaining_samples,
         chunks
       ) do
    {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary(), encoder}
  end

  defp take_samples(encoder, 0, chunks) do
    {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary(), encoder}
  end

  defp take_samples(encoder, remaining_samples, chunks) do
    encoder = load_run(encoder)
    sample_count = min(encoder.current_remaining_samples, remaining_samples)

    chunk =
      case encoder.current_kind do
        :tone -> tone(encoder.tone_sample_index, sample_count, encoder.config)
        :silence -> :binary.copy(<<0, 0>>, sample_count)
      end

    encoder = %{
      encoder
      | current_remaining_samples: encoder.current_remaining_samples - sample_count,
        tone_sample_index: encoder.tone_sample_index + sample_count
    }

    encoder = if encoder.current_remaining_samples == 0, do: finish_run(encoder), else: encoder

    take_samples(encoder, remaining_samples - sample_count, [chunk | chunks])
  end

  defp load_run(%__MODULE__{current_kind: nil, runs: [{kind, units} | runs]} = encoder) do
    %{
      encoder
      | current_kind: kind,
        current_remaining_samples: units * unit_samples(encoder.config),
        runs: runs,
        tone_sample_index: 0
    }
  end

  defp load_run(encoder), do: encoder

  defp finish_run(encoder) do
    %{encoder | current_kind: nil, current_remaining_samples: 0, tone_sample_index: 0}
  end

  defp tone(start_index, sample_count, config) do
    radians_per_sample = 2.0 * :math.pi() * config.frequency_hz / config.sample_rate

    for sample_index <- start_index..(start_index + sample_count - 1), into: <<>> do
      sample = round(:math.sin(sample_index * radians_per_sample) * config.amplitude)
      <<sample::signed-little-16>>
    end
  end

  defp unit_samples(config),
    do: div(config.sample_rate * config.unit_duration_ms, 1_000)
end
