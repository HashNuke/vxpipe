defmodule Vxpipe.CallEngine.Speech.Duplex.TurnInference do
  @moduledoc """
  Infers caller turn boundaries for a GPT-Live-style duplex provider.

  The provider reports untimed-transcript facts without item IDs, completed-turn
  events or interruption events. This module groups its input transcript
  fragments into inferred turns for publication and call records only. An
  inferred boundary never triggers, delays or blocks the model's response.

  Pure and clock-free: every duration is audio-time milliseconds, never wall
  clock. The adapter reports the caller audio it has pushed with
  `audio_pushed/2`; it reports provider fragments with `input_fragment/2`.
  """

  @default_gap_ms 800

  @enforce_keys [:gap_ms]
  defstruct [:gap_ms, :turn, :last_end_ms, :since_fragment_ms, :text]

  @type t :: %__MODULE__{
          gap_ms: pos_integer(),
          turn: reference() | nil,
          last_end_ms: non_neg_integer() | nil,
          since_fragment_ms: non_neg_integer(),
          text: binary()
        }

  @type fragment :: %{
          required(:text) => binary(),
          required(:start_ms) => non_neg_integer(),
          required(:end_ms) => non_neg_integer()
        }

  @type event :: {atom(), keyword()}

  @doc "Build inference state. The gap defaults to 800 ms."
  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_gap}
  def new(options \\ [])

  def new(options) when is_list(options) do
    case Keyword.get(options, :gap_ms, @default_gap_ms) do
      gap when is_integer(gap) and gap > 0 ->
        {:ok, %__MODULE__{gap_ms: gap, since_fragment_ms: 0, text: ""}}

      _invalid ->
        {:error, :invalid_gap}
    end
  end

  def new(_options), do: {:error, :invalid_gap}

  @doc "Report one provider input transcript fragment and any inferred events."
  @spec input_fragment(t(), fragment()) :: {t(), [event()]}
  def input_fragment(%__MODULE__{} = state, fragment) do
    case normalize(fragment) do
      {:ok, "", _start_ms, _end_ms} -> {state, []}
      {:ok, text, start_ms, end_ms} -> advance(state, text, start_ms, end_ms)
      :error -> {state, []}
    end
  end

  @doc """
  Report caller audio pushed since the last input fragment. The open turn closes
  once that audio reaches the gap.
  """
  @spec audio_pushed(t(), non_neg_integer()) :: {t(), [event()]}
  def audio_pushed(%__MODULE__{turn: nil} = state, duration_ms)
      when is_integer(duration_ms) and duration_ms >= 0,
      do: {state, []}

  def audio_pushed(%__MODULE__{} = state, duration_ms)
      when is_integer(duration_ms) and duration_ms >= 0 do
    since = state.since_fragment_ms + duration_ms

    if since >= state.gap_ms do
      close(state)
    else
      {%{state | since_fragment_ms: since}, []}
    end
  end

  def audio_pushed(state, _duration_ms), do: {state, []}

  @doc "Session end: close any open turn so its text is not lost."
  @spec finish(t()) :: {t(), [event()]}
  def finish(%__MODULE__{turn: nil} = state), do: {state, []}
  def finish(%__MODULE__{} = state), do: close(state)

  @doc "Whether a caller turn is currently open."
  @spec status(t()) :: :open | :idle
  def status(%__MODULE__{turn: nil}), do: :idle
  def status(%__MODULE__{}), do: :open

  defp advance(state, text, start_ms, end_ms) do
    cond do
      state.turn == nil ->
        open(state, text, end_ms)

      start_ms - state.last_end_ms > state.gap_ms ->
        {state, close_events} = close(state)
        {state, open_events} = open(state, text, end_ms)
        {state, close_events ++ open_events}

      true ->
        append(state, text, end_ms)
    end
  end

  defp open(state, text, end_ms) do
    turn = make_ref()

    events = [
      {:speech_started, [turn_ref: turn]},
      {:input_transcript, [turn_ref: turn, text: text, final: false]}
    ]

    {%{state | turn: turn, text: text, last_end_ms: end_ms, since_fragment_ms: 0}, events}
  end

  defp append(state, text, end_ms) do
    text = state.text <> text

    events = [{:input_transcript, [turn_ref: state.turn, text: text, final: false]}]

    {%{
       state
       | text: text,
         last_end_ms: max(state.last_end_ms, end_ms),
         since_fragment_ms: 0
     }, events}
  end

  defp close(state) do
    events = [
      {:input_transcript, [turn_ref: state.turn, text: state.text, final: true]},
      {:turn_ended, [turn_ref: state.turn, text: state.text, endpointing: :inferred_gap]}
    ]

    {%{state | turn: nil, last_end_ms: nil, since_fragment_ms: 0, text: ""}, events}
  end

  defp normalize(%{text: text, start_ms: start_ms, end_ms: end_ms})
       when is_binary(text) and is_integer(start_ms) and is_integer(end_ms) and start_ms >= 0 and
              end_ms >= start_ms,
       do: {:ok, text, start_ms, end_ms}

  defp normalize(_fragment), do: :error
end
