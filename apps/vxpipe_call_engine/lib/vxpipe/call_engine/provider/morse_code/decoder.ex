defmodule Vxpipe.CallEngine.Provider.MorseCode.Decoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.MorseCode.{Alphabet, Config}

  @timing_tolerance_windows 1

  @enforce_keys [
    :config,
    :dot_windows,
    :end_gap_windows,
    :letter_gap_windows,
    :maximum_windows,
    :window_bytes,
    :word_gap_windows
  ]
  defstruct @enforce_keys ++
              [
                carry: <<>>,
                current_kind: nil,
                current_windows: 0,
                marks: "",
                started?: false,
                text: "",
                total_windows: 0
              ]

  @type event :: :started | {:partial, String.t()} | {:final, String.t()}
  @type error ::
          :incomplete_sample
          | :invalid_timing
          | :signal_too_long
          | :transcript_too_large
          | :unsupported_frequency
          | :unsupported_signal

  @type t :: %__MODULE__{
          config: Config.t(),
          dot_windows: pos_integer(),
          end_gap_windows: pos_integer(),
          letter_gap_windows: pos_integer(),
          maximum_windows: pos_integer(),
          window_bytes: pos_integer(),
          word_gap_windows: pos_integer(),
          carry: binary(),
          current_kind: :tone | :silence | nil,
          current_windows: non_neg_integer(),
          marks: String.t(),
          started?: boolean(),
          text: String.t(),
          total_windows: non_neg_integer()
        }

  @spec new(Config.t()) :: {:ok, t()}
  def new(%Config{} = config) do
    dot_windows = div(config.unit_duration_ms, config.window_duration_ms)

    {:ok,
     %__MODULE__{
       config: config,
       dot_windows: dot_windows,
       end_gap_windows: config.end_gap_units * dot_windows,
       letter_gap_windows: 3 * dot_windows,
       maximum_windows: div(config.maximum_utterance_ms, config.window_duration_ms),
       window_bytes: div(config.sample_rate * config.window_duration_ms, 1_000) * 2,
       word_gap_windows: 7 * dot_windows
     }}
  end

  @spec push(t(), binary()) :: {:ok, t(), [event()]} | {:error, error()}
  def push(%__MODULE__{} = decoder, pcm) when is_binary(pcm) do
    process_windows(decoder.carry <> pcm, %{decoder | carry: <<>>}, [])
  end

  @spec flush(t()) :: {:ok, t(), [event()]} | {:error, error()}
  def flush(%__MODULE__{carry: carry}) when byte_size(carry) > 0,
    do: {:error, :incomplete_sample}

  def flush(%__MODULE__{started?: false} = decoder),
    do: {:ok, reset(decoder), []}

  def flush(%__MODULE__{current_kind: :tone} = decoder) do
    with {:ok, decoder} <- finish_tone(decoder),
         {:ok, decoder, events} <- finish_utterance(decoder) do
      {:ok, reset(decoder), events}
    end
  end

  def flush(%__MODULE__{current_kind: :silence} = decoder) do
    with :ok <- valid_final_silence?(decoder),
         {:ok, decoder, events} <- finish_utterance(decoder) do
      {:ok, reset(decoder), events}
    end
  end

  def flush(%__MODULE__{} = decoder), do: {:ok, reset(decoder), []}

  defp process_windows(binary, decoder, events) when byte_size(binary) < decoder.window_bytes do
    {:ok, %{decoder | carry: binary}, Enum.reverse(events)}
  end

  defp process_windows(binary, decoder, events) do
    <<window::binary-size(decoder.window_bytes), rest::binary>> = binary

    with :ok <- within_duration?(decoder),
         {:ok, kind} <- classify(window, decoder.config),
         {:ok, decoder, emitted} <- advance(decoder, kind) do
      process_windows(rest, decoder, Enum.reverse(emitted, events))
    end
  end

  defp within_duration?(decoder) do
    if decoder.total_windows < decoder.maximum_windows,
      do: :ok,
      else: {:error, :signal_too_long}
  end

  defp classify(window, config) do
    samples = for <<sample::signed-little-16 <- window>>, do: sample
    energy = Enum.reduce(samples, 0, fn sample, total -> total + sample * sample end)
    threshold_energy = config.detection_threshold * config.detection_threshold * length(samples)

    if energy <= threshold_energy do
      {:ok, :silence}
    else
      frequency = estimated_frequency(samples, config.sample_rate, config.detection_threshold)

      if abs(frequency - config.frequency_hz) <= config.frequency_tolerance_hz,
        do: {:ok, :tone},
        else: {:error, :unsupported_frequency}
    end
  end

  defp estimated_frequency(samples, sample_rate, threshold) do
    {_last_sign, crossings} =
      Enum.reduce(samples, {nil, 0}, fn sample, {last_sign, crossings} ->
        sign = sample_sign(sample, threshold)

        cond do
          sign == nil -> {last_sign, crossings}
          last_sign == nil -> {sign, crossings}
          sign == last_sign -> {sign, crossings}
          true -> {sign, crossings + 1}
        end
      end)

    crossings * sample_rate / (2 * max(length(samples) - 1, 1))
  end

  defp sample_sign(sample, threshold) when sample > threshold, do: :positive
  defp sample_sign(sample, threshold) when sample < -threshold, do: :negative
  defp sample_sign(_sample, _threshold), do: nil

  defp advance(%{current_kind: nil} = decoder, kind) do
    events = if kind == :tone, do: [:started], else: []

    {:ok,
     %{
       decoder
       | current_kind: kind,
         current_windows: 1,
         started?: kind == :tone,
         total_windows: decoder.total_windows + 1
     }, events}
  end

  defp advance(%{current_kind: kind} = decoder, kind) do
    decoder = %{
      decoder
      | current_windows: decoder.current_windows + 1,
        total_windows: decoder.total_windows + 1
    }

    if kind == :silence, do: silence_checkpoint(decoder), else: {:ok, decoder, []}
  end

  defp advance(%{current_kind: :tone} = decoder, :silence) do
    with {:ok, decoder} <- finish_tone(decoder) do
      {:ok,
       %{
         decoder
         | current_kind: :silence,
           current_windows: 1,
           total_windows: decoder.total_windows + 1
       }, []}
    end
  end

  defp advance(%{current_kind: :silence} = decoder, :tone) do
    with {:ok, decoder, events} <- finish_silence(decoder) do
      started_events = if decoder.started?, do: [], else: [:started]

      {:ok,
       %{
         decoder
         | current_kind: :tone,
           current_windows: 1,
           started?: true,
           total_windows: decoder.total_windows + 1
       }, events ++ started_events}
    end
  end

  defp silence_checkpoint(%{started?: false} = decoder), do: {:ok, decoder, []}

  defp silence_checkpoint(%{current_windows: windows} = decoder)
       when windows == decoder.letter_gap_windows do
    finish_letter(decoder)
  end

  defp silence_checkpoint(%{current_windows: windows} = decoder)
       when windows == decoder.word_gap_windows do
    {:ok, append_word_gap(decoder), []}
  end

  defp silence_checkpoint(%{current_windows: windows} = decoder)
       when windows == decoder.end_gap_windows do
    finish_utterance(decoder)
  end

  defp silence_checkpoint(decoder), do: {:ok, decoder, []}

  defp finish_tone(decoder) do
    cond do
      near?(decoder.current_windows, decoder.dot_windows) ->
        append_mark(decoder, ".")

      near?(decoder.current_windows, decoder.dot_windows * 3) ->
        append_mark(decoder, "-")

      true ->
        {:error, :invalid_timing}
    end
  end

  defp append_mark(decoder, mark) do
    marks = decoder.marks <> mark

    if byte_size(marks) <= 8,
      do: {:ok, %{decoder | marks: marks}},
      else: {:error, :unsupported_signal}
  end

  defp finish_silence(%{started?: false} = decoder), do: {:ok, decoder, []}

  defp finish_silence(decoder) do
    cond do
      near?(decoder.current_windows, decoder.dot_windows) ->
        {:ok, decoder, []}

      near?(decoder.current_windows, decoder.letter_gap_windows) ->
        finish_letter(decoder)

      near?(decoder.current_windows, decoder.word_gap_windows) ->
        with {:ok, decoder, events} <- finish_letter(decoder) do
          {:ok, append_word_gap(decoder), events}
        end

      decoder.current_windows >= decoder.end_gap_windows - @timing_tolerance_windows ->
        finish_utterance(decoder)

      true ->
        {:error, :invalid_timing}
    end
  end

  defp finish_letter(%{marks: ""} = decoder), do: {:ok, decoder, []}

  defp finish_letter(decoder) do
    with {:ok, character} <- Alphabet.decode(decoder.marks),
         text = decoder.text <> character,
         true <- byte_size(text) <= decoder.config.maximum_text_bytes do
      {:ok, %{decoder | marks: "", text: text}, [{:partial, text}]}
    else
      {:error, _reason} -> {:error, :unsupported_signal}
      false -> {:error, :transcript_too_large}
    end
  end

  defp append_word_gap(%{text: ""} = decoder), do: decoder

  defp append_word_gap(decoder) do
    text = String.trim_trailing(decoder.text) <> " "
    %{decoder | text: text}
  end

  defp finish_utterance(decoder) do
    with {:ok, decoder, partial_events} <- finish_letter(decoder) do
      text = String.trim(decoder.text)

      if text == "" do
        {:ok, %{decoder | started?: false}, partial_events}
      else
        decoder = %{decoder | marks: "", started?: false, text: "", total_windows: 0}
        {:ok, decoder, partial_events ++ [{:final, text}]}
      end
    end
  end

  defp valid_final_silence?(decoder) do
    windows = decoder.current_windows

    if near?(windows, decoder.dot_windows) or near?(windows, decoder.letter_gap_windows) or
         near?(windows, decoder.word_gap_windows) or
         windows >= decoder.end_gap_windows - @timing_tolerance_windows do
      :ok
    else
      {:error, :invalid_timing}
    end
  end

  defp near?(actual, expected), do: abs(actual - expected) <= @timing_tolerance_windows

  defp reset(decoder) do
    %{
      decoder
      | carry: <<>>,
        current_kind: nil,
        current_windows: 0,
        marks: "",
        started?: false,
        text: "",
        total_windows: 0
    }
  end
end
