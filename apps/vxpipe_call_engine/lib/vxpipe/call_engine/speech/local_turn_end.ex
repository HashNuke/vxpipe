defmodule Vxpipe.CallEngine.Speech.LocalTurnEnd do
  @moduledoc """
  Pure turn authority for human STT with local VAD (`vad: true`).

  Local Silero owns both boundaries of one canonical turn. Provider turns are
  segments: their text joins the canonical turn and their ends never end it.
  The turn ends after local silence, a resume window and, when the provider can
  finalize on request, its finalized text. This follows Pipecat's speech-timeout
  stop strategy:

  - Local speech start opens a turn; speech resuming cancels pending end work.
  - Local speech end asks the owner to arm the resume window (`:arm_hangover`).
  - When the window elapses with already-final text, the turn ends at once.
    Otherwise the owner requests provider finalization (`:finalize`, only for
    providers declaring it) and arms a bounded wait (`:arm_final_wait`).
  - A provider final during that wait ends the turn. When the wait expires, the
    turn ends with the latest text, which may be empty.
  - Provider text without a local onset starts the turn, so missed onsets still
    produce one bounded turn.

  The owner holds timers and calls `hangover_elapsed/1` or `final_wait_elapsed/1`
  when they fire. Elapsed notifications outside their phase are ignored, so a
  cancelled timer that already fired has no effect. Ended provider references are
  retained in a bounded recent set; later evidence for them is ignored.

  Emissions are `{kind, fields}` pairs for the outer semantic channel. Actions
  are owner instructions in execution order. Failures use fixed reasons and never
  include transcript text.

  The turn end carries the latest provider request identity and the summed
  provider-reported audio duration of its segments, so caller usage stays
  attributed to the turn.
  """

  alias Vxpipe.CallEngine.Speech.Event

  @max_retired 64
  @native_kinds [:speech_started, :transcript, :turn_ended, :eager_turn_ended, :turn_resumed]

  @enforce_keys [:finalize?]
  defstruct finalize?: false,
            active: nil,
            phase: :idle,
            speaking?: false,
            committed: "",
            segment: nil,
            segment_text: "",
            published: "",
            request_id: nil,
            duration: nil,
            retired: []

  @type emission :: {atom(), keyword()}
  @type action :: :arm_hangover | :finalize | :arm_final_wait | :cancel_timers
  @type result :: {:ok, t(), [emission()], [action()]} | {:error, atom()}
  @type t :: %__MODULE__{}

  @doc "Build state. `finalize?` declares that the recognizer finalizes on request."
  @spec new(keyword()) :: t()
  def new(options) when is_list(options) do
    case Keyword.validate(options, [:finalize?]) do
      {:ok, [finalize?: finalize?]} when is_boolean(finalize?) ->
        %__MODULE__{finalize?: finalize?}

      _invalid ->
        raise ArgumentError, "LocalTurnEnd.new/1 expects [finalize?: boolean]"
    end
  end

  @doc "The open canonical turn, if any."
  @spec active(t()) :: reference() | nil
  def active(%__MODULE__{active: active}), do: active

  @doc "Whether local speech is currently confirmed."
  @spec speaking?(t()) :: boolean()
  def speaking?(%__MODULE__{speaking?: speaking?}), do: speaking?

  @doc "Local detector confirmed speech."
  @spec acoustic_started(t()) :: result()
  def acoustic_started(%__MODULE__{active: nil} = state) do
    {state, emissions} = open(%{state | speaking?: true})
    {:ok, state, emissions, []}
  end

  def acoustic_started(%__MODULE__{phase: :open} = state),
    do: {:ok, %{state | speaking?: true}, [], []}

  def acoustic_started(%__MODULE__{} = state),
    do: {:ok, %{state | speaking?: true, phase: :open}, [], [:cancel_timers]}

  @doc "Local detector confirmed silence after speech."
  @spec acoustic_ended(t()) :: result()
  def acoustic_ended(%__MODULE__{active: nil} = state),
    do: {:ok, %{state | speaking?: false}, [], []}

  def acoustic_ended(%__MODULE__{} = state),
    do: {:ok, %{state | speaking?: false, phase: :hangover}, [], [:arm_hangover]}

  @doc "The resume window armed by `:arm_hangover` elapsed."
  @spec hangover_elapsed(t()) :: result()
  def hangover_elapsed(%__MODULE__{phase: :hangover, speaking?: false} = state) do
    if is_nil(state.segment) and nonempty?(state.committed) do
      finish(state, [])
    else
      actions = if state.finalize?, do: [:finalize, :arm_final_wait], else: [:arm_final_wait]
      {:ok, %{state | phase: :finalizing}, [], actions}
    end
  end

  def hangover_elapsed(%__MODULE__{} = state), do: {:ok, state, [], []}

  @doc "The bounded wait armed by `:arm_final_wait` elapsed."
  @spec final_wait_elapsed(t()) :: result()
  def final_wait_elapsed(%__MODULE__{phase: :finalizing} = state), do: finish(state, [])
  def final_wait_elapsed(%__MODULE__{} = state), do: {:ok, state, [], []}

  @doc "Consume one provider-native semantic event."
  @spec native(t(), Event.t() | term()) :: result()
  def native(%__MODULE__{} = state, %Event{kind: kind, turn_ref: native} = event)
      when kind in @native_kinds and is_reference(native) do
    cond do
      native in state.retired ->
        {:ok, state, [], []}

      kind == :transcript and is_binary(event.text) ->
        text(identify(state, event), native, event.text)

      kind == :turn_ended and is_binary(event.text) ->
        state = state |> identify(event) |> add_duration(event.audio_duration_ms)
        final(state, native, event.text)

      kind in [:speech_started, :eager_turn_ended, :turn_resumed] ->
        {:ok, state, [], []}

      true ->
        {:error, :invalid_event}
    end
  end

  def native(%__MODULE__{}, _event), do: {:error, :invalid_event}

  defp identify(state, %Event{provider_request_id: id}) when is_binary(id),
    do: %{state | request_id: id}

  defp identify(state, _event), do: state

  defp add_duration(state, ms) when is_integer(ms) and ms >= 0,
    do: %{state | duration: (state.duration || 0) + ms}

  defp add_duration(state, _ms), do: state

  defp text(state, native, text) do
    if nonempty?(text) do
      state = switch_segment(state, native)
      {state, starts, actions} = ensure_open(state)
      state = %{state | segment: native, segment_text: text}
      {state, transcripts} = publish(state)
      {:ok, state, starts ++ transcripts, actions}
    else
      {:ok, state, [], []}
    end
  end

  defp final(state, native, text) do
    final_text =
      cond do
        nonempty?(text) -> text
        native == state.segment -> state.segment_text
        true -> ""
      end

    cond do
      nonempty?(final_text) ->
        state = switch_segment(state, native)
        {state, starts, actions} = ensure_open(state)

        state = %{
          retire(state, native)
          | segment: nil,
            segment_text: "",
            committed: join(state.committed, final_text)
        }

        {state, transcripts} = publish(state)
        settle_final(state, starts ++ transcripts, actions)

      native == state.segment ->
        settle_final(%{retire(state, native) | segment: nil, segment_text: ""}, [], [])

      true ->
        {:ok, retire(state, native), [], []}
    end
  end

  defp settle_final(%{phase: :finalizing} = state, emissions, _actions),
    do: finish(state, emissions)

  defp settle_final(state, emissions, actions), do: {:ok, state, emissions, actions}

  # A provider that starts a new turn without ending the previous one keeps the
  # earlier words as committed text for this canonical turn.
  defp switch_segment(%{segment: nil} = state, _native), do: state
  defp switch_segment(%{segment: native} = state, native), do: state

  defp switch_segment(state, _native) do
    %{
      retire(state, state.segment)
      | committed: join(state.committed, state.segment_text),
        segment: nil,
        segment_text: ""
    }
  end

  defp ensure_open(%{active: nil} = state) do
    {state, emissions} = open(state)

    if state.speaking?,
      do: {state, emissions, []},
      else: {%{state | phase: :hangover}, emissions, [:arm_hangover]}
  end

  defp ensure_open(state), do: {state, [], []}

  defp open(state) do
    turn = make_ref()

    {%{state | active: turn, phase: :open},
     [{:speech_started, [turn_ref: turn] ++ request_fields(state)}]}
  end

  defp publish(state) do
    text = cumulative(state)

    if text == state.published,
      do: {state, []},
      else:
        {%{state | published: text},
         [{:transcript, [turn_ref: state.active, text: text] ++ request_fields(state)}]}
  end

  defp finish(state, emissions) do
    ended =
      {:turn_ended,
       [turn_ref: state.active, text: cumulative(state), endpointing: :local_gap] ++
         request_fields(state) ++ duration_fields(state)}

    state = if state.segment, do: retire(state, state.segment), else: state

    {:ok,
     %{
       state
       | active: nil,
         phase: :idle,
         committed: "",
         segment: nil,
         segment_text: "",
         published: "",
         duration: nil
     }, emissions ++ [ended], [:cancel_timers]}
  end

  defp retire(state, native) do
    if native in state.retired,
      do: state,
      else: %{state | retired: Enum.take([native | state.retired], @max_retired)}
  end

  defp request_fields(%{request_id: id}) when is_binary(id), do: [provider_request_id: id]
  defp request_fields(_state), do: []

  defp duration_fields(%{duration: ms}) when is_integer(ms), do: [audio_duration_ms: ms]
  defp duration_fields(_state), do: []

  defp cumulative(state), do: join(state.committed, state.segment_text)

  defp join("", right), do: right
  defp join(left, ""), do: left
  defp join(left, right), do: String.trim_trailing(left) <> " " <> String.trim_leading(right)

  defp nonempty?(text), do: String.trim(text) != ""
end
