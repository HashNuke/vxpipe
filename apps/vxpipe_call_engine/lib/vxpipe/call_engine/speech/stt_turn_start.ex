defmodule Vxpipe.CallEngine.Speech.STTTurnStart do
  @moduledoc """
  Pure, bounded coordinator mapping provider-native STT turn evidence to one
  canonical turn reference per turn.

  The coordinator consumes existing semantic `Speech.Event` structs carrying
  provider-native turn references and returns canonical semantic emissions as
  `{kind, keyword_fields}` pairs. The owning wrapper remains the sole producer
  on the outer semantic channel; this module never emits, acknowledges, logs
  transcript text, or touches provider APIs.

  Contract summary:

  - `new/0` defaults to transcript start (`vad: false`). `new/1` accepts a
    boolean or `[vad: boolean]`.
  - A native `speech_started` event is correlation evidence only. It never
    emits; it records which canonical reference a provider turn maps to.
  - The first nonempty transcript (trimmed text is not empty) for a turn emits
    `speech_started` followed by `transcript`, exactly once per canonical turn.
    Empty and repeated interim text emits nothing; revised text emits one
    `transcript` update on the same canonical reference.
  - A final-only `turn_ended` with text emits `speech_started`, `transcript`
    and `turn_ended` in that order. A final repeating interim text emits only
    `turn_ended`; a revised final emits `transcript` then `turn_ended`.
  - Canonical emission order inside one result is always
    `speech_started`, `transcript`, control marks (`eager_turn_ended`,
    `turn_resumed`), `turn_ended`. Buffered controls are flushed after the
    transcript, never before it. Controls for a turn that never produces words
    are dropped rather than emitted with empty initial text.
  - Native `eager_turn_ended` and `turn_resumed` preserve the mapped canonical
    reference. They are emitted immediately only after that turn's canonical
    start already carried transcript words; earlier arrivals are held and
    flushed in arrival order after the transcript. Consecutive duplicate
    controls of the same kind are suppressed. Per-turn buffering is bounded at
    `max_controls/0` entries; further buffered controls fail with the fixed
    reason `:turn_overflow`.
  - With `vad: true`, `activity_started/1` emits one early `speech_started`
    for local onset when no turn is open. When provider hints for an unstarted
    turn already exist, local onset adopts the earliest such mapping, so
    same-audio text and finals join the acoustic turn instead of stalling
    queued behind an unbound one. Duplicate local starts while a turn is open
    emit nothing. When local onset never arrives, transcript fallback behaves
    exactly like the default mode.
  - An empty final settles an already-started turn (emitting `turn_ended` with
    the provider's endpointing) but never starts a new one. A native hint
    followed by an empty final in default mode silently closes that
    correlation: no start and no end are emitted, and the native reference is
    tombstoned (see retired references below).
  - Distinct provider turns always map to distinct canonical references. Turns
    that arrive while another turn is active are queued and drained in creation
    order when the active turn settles. A queued final seals its entry:
    later partials, controls and finals for the sealed turn are ignored, so
    finalized content can never be revised. A drained start and transcript use
    the sealing final's `provider_request_id` when present, so a final-only
    queued transcript carries the final's request identity.
  - A queued interim plus a blank final seals the queued words: settling the
    active turn afterwards drains the queued start, transcript (with the
    interim words and the blank final's request identity) and end.
  - `turn_ended` and `eager_turn_ended` emissions propagate the matching
    native `endpointing`, `provider_request_id` and `audio_duration_ms`.
    Starts and transcripts propagate `provider_request_id` when present.
  - Settled and silently closed native references retire into a bounded
    tombstone set (`max_retired/0` entries). Every later event carrying a
    retired reference is ignored, so a stale final can never settle a newer
    turn and a stale reference is never rebound to a new acoustic onset, even
    after the settled entry itself is reclaimed for reuse. Tombstones are
    never silently discarded: once `max_retired/0` references are retained,
    correlating a new provider-native reference fails with the fixed reason
    `:turn_overflow`. The coordinator therefore stays correct for very long
    calls but does not promise unbounded calls; the owning wrapper must treat
    `:turn_overflow` as an explicit failure signal.
  - The turn map is bounded at `max_turns/0` entries (9, matching the
    Google provider session turn bound of 8 pending finals plus 1 active, which
    this module does not change). Settled
    turns are reclaimed for reuse while their tombstones are kept; a new
    distinct turn with no reclaimable entry fails with the fixed reason
    `:turn_overflow`.
  - Failures use fixed safe reasons only (`:invalid_event`,
    `:unsupported_event`, `:turn_overflow`, `:vad_disabled`) and never
    include transcript text. Transcript content is inspected only for
    trimmed emptiness and same-turn revision equality.

  Correlation limits of the suggested API (no ambiguity is papered over):

  - Settling a VAD-started turn that truly has no words depends on the
    provider eventually supplying its required boundary event; this module
    invents no timeout. Proposed addition: a parent-owned
    `settle_acoustic(state)` used only with existing session
    failure/timeout handling, so no-word completion stays explicit.
  """

  alias Vxpipe.CallEngine.Speech.Event

  @max_turns 9
  @max_controls 4
  @max_retired 4096

  @native_kinds [:speech_started, :transcript, :turn_ended, :eager_turn_ended, :turn_resumed]

  @endpointing [:provider_semantic, :provider_gap, :local_gap, :inferred_gap, :external]

  @enforce_keys [:vad]
  defstruct vad: false, active: nil, order: [], turns: %{}, native: %{}, retired: nil

  @type emission :: {atom(), keyword()}
  @type result :: {:ok, t(), [emission()]} | {:error, atom()}
  @type t :: %__MODULE__{}

  @doc "Build coordinator state. Defaults to transcript start (`vad: false`)."
  @spec new() :: t()
  def new, do: %__MODULE__{vad: false, retired: MapSet.new()}

  @doc "Build coordinator state with an explicit onset mode."
  @spec new(boolean() | keyword()) :: t()
  def new(vad) when is_boolean(vad), do: %__MODULE__{vad: vad, retired: MapSet.new()}

  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:vad] == [] and
         is_boolean(Keyword.get(opts, :vad, false)) do
      %__MODULE__{vad: Keyword.get(opts, :vad, false), retired: MapSet.new()}
    else
      raise ArgumentError, "STTTurnStart.new/1 expects a boolean or [vad: boolean]"
    end
  end

  def new(_vad) do
    raise ArgumentError, "STTTurnStart.new/1 expects a boolean or [vad: boolean]"
  end

  @doc "Maximum number of tracked turns, settled entries included."
  @spec max_turns() :: pos_integer()
  def max_turns, do: @max_turns

  @doc "Maximum number of buffered control marks held per unstarted turn."
  @spec max_controls() :: pos_integer()
  def max_controls, do: @max_controls

  @doc "Maximum number of retired native references retained as tombstones."
  @spec max_retired() :: pos_integer()
  def max_retired, do: @max_retired

  @doc "Number of turns currently open or queued."
  @spec pending_count(t()) :: non_neg_integer()
  def pending_count(%__MODULE__{turns: turns}) do
    Enum.count(turns, fn {_canon, entry} -> not entry.ended end)
  end

  @doc """
  Report local detector onset. Emits one early `speech_started` when VAD is
  enabled and no turn is open; otherwise emits nothing. Adopts the earliest
  pending unstarted native mapping when one exists. Fails with
  `:vad_disabled` when VAD is off.
  """
  @spec activity_started(t()) :: result()
  def activity_started(%__MODULE__{vad: false}), do: {:error, :vad_disabled}

  def activity_started(%__MODULE__{active: active} = state) when not is_nil(active),
    do: {:ok, state, []}

  def activity_started(%__MODULE__{} = state) do
    case earliest_pending_hint(state) do
      nil ->
        with {:ok, state, canon} <- allocate(state, nil) do
          entry = Map.fetch!(state.turns, canon)
          state = put_entry(state, canon, %{entry | started: true})
          {:ok, %{state | active: canon}, [{:speech_started, [turn_ref: canon]}]}
        end

      canon ->
        entry = Map.fetch!(state.turns, canon)
        state = put_entry(state, canon, %{entry | started: true})
        {:ok, %{state | active: canon}, [{:speech_started, [turn_ref: canon]}]}
    end
  end

  @doc """
  Consume one provider-native semantic event and return canonical emissions
  in delivery order.
  """
  @spec native(t(), Event.t() | term()) :: result()
  def native(%__MODULE__{} = state, %Event{kind: kind} = event)
      when kind in @native_kinds do
    case validate_native(event) do
      :ok -> dispatch(state, event)
      {:error, _reason} = error -> error
    end
  end

  def native(%__MODULE__{}, %Event{kind: kind}) when is_atom(kind) and not is_nil(kind),
    do: {:error, :unsupported_event}

  def native(%__MODULE__{}, _event), do: {:error, :invalid_event}

  defp validate_native(%Event{kind: :speech_started, turn_ref: turn_ref}) do
    if is_reference(turn_ref), do: :ok, else: {:error, :invalid_event}
  end

  defp validate_native(%Event{kind: :transcript, turn_ref: turn_ref, text: text}) do
    if is_reference(turn_ref) and is_binary(text), do: :ok, else: {:error, :invalid_event}
  end

  defp validate_native(%Event{
         kind: kind,
         turn_ref: turn_ref,
         text: text,
         endpointing: endpointing
       })
       when kind in [:turn_ended, :eager_turn_ended] do
    if is_reference(turn_ref) and is_binary(text) and endpointing in @endpointing,
      do: :ok,
      else: {:error, :invalid_event}
  end

  defp validate_native(%Event{kind: :turn_resumed, turn_ref: turn_ref}) do
    if is_reference(turn_ref), do: :ok, else: {:error, :invalid_event}
  end

  defp dispatch(state, %Event{kind: :speech_started, turn_ref: native_ref}) do
    if retired?(state, native_ref) do
      {:ok, state, []}
    else
      case correlate(state, native_ref) do
        {:ok, state, _canon} -> {:ok, state, []}
        {:error, _reason} = error -> error
      end
    end
  end

  defp dispatch(state, %Event{kind: :transcript} = event) do
    cond do
      retired?(state, event.turn_ref) ->
        {:ok, state, []}

      nonempty?(event.text) ->
        with {:ok, state, canon} <- correlate(state, event.turn_ref) do
          on_text(state, canon, event.text, event.provider_request_id)
        end

      true ->
        {:ok, state, []}
    end
  end

  defp dispatch(state, %Event{kind: :turn_ended} = event) do
    on_end(state, event)
  end

  defp dispatch(state, %Event{kind: kind} = event)
       when kind in [:eager_turn_ended, :turn_resumed] do
    if retired?(state, event.turn_ref) do
      {:ok, state, []}
    else
      with {:ok, state, canon} <- correlate(state, event.turn_ref) do
        on_mark(state, canon, event)
      end
    end
  end

  defp on_text(state, canon, text, provider_request_id) do
    entry = Map.fetch!(state.turns, canon)

    cond do
      entry.ended ->
        {:ok, state, []}

      not is_nil(entry.pending_end) ->
        {:ok, state, []}

      canon == state.active ->
        if entry.last_text == text do
          {:ok, state, []}
        else
          marks = Enum.map(entry.marks, &canonical_mark(canon, &1))
          state = put_entry(state, canon, %{entry | last_text: text, marks: []})

          {:ok, state,
           [{:transcript, transcript_fields(canon, text, provider_request_id)}] ++ marks}
        end

      is_nil(state.active) ->
        activate_with_text(state, canon, text, provider_request_id)

      true ->
        pending = %{entry | pending_text: text, pending_prid: provider_request_id}
        {:ok, put_entry(state, canon, pending), []}
    end
  end

  defp on_end(state, event) do
    if retired?(state, event.turn_ref) do
      {:ok, state, []}
    else
      case Map.fetch(state.native, event.turn_ref) do
        {:ok, canon} -> settle_mapped(state, canon, event)
        :error -> settle_unmapped(state, event)
      end
    end
  end

  defp settle_mapped(state, canon, event) do
    entry = Map.fetch!(state.turns, canon)

    cond do
      entry.ended ->
        {:ok, state, []}

      not is_nil(entry.pending_end) ->
        {:ok, state, []}

      nonempty?(event.text) ->
        if canon == state.active or is_nil(state.active) do
          settle_now(state, canon, event)
        else
          pending = %{entry | pending_text: event.text, pending_end: event}
          {:ok, put_entry(state, canon, pending), []}
        end

      canon == state.active ->
        settle_now(state, canon, event)

      entry.started or not is_nil(entry.pending_text) or not is_nil(entry.last_text) ->
        pending = %{entry | pending_end: event}
        {:ok, put_entry(state, canon, pending), []}

      true ->
        silently_close(state, canon, event.turn_ref)
    end
  end

  defp settle_unmapped(state, event) do
    if nonempty?(event.text) do
      with {:ok, state, canon} <- correlate(state, event.turn_ref) do
        if canon == state.active or is_nil(state.active) do
          settle_now(state, canon, event)
        else
          entry = Map.fetch!(state.turns, canon)

          pending = %{
            entry
            | pending_text: event.text,
              pending_prid: event.provider_request_id,
              pending_end: event
          }

          {:ok, put_entry(state, canon, pending), []}
        end
      end
    else
      case acoustic_unbound(state) do
        nil ->
          with {:ok, state} <- add_retired(state, event.turn_ref) do
            {:ok, state, []}
          end

        canon ->
          settle_now(bind(state, event.turn_ref, canon), canon, event)
      end
    end
  end

  defp settle_now(state, canon, event) do
    entry = Map.fetch!(state.turns, canon)

    with {:ok, state} <- add_retired(state, entry.native) do
      entry = Map.fetch!(state.turns, canon)
      start = if entry.started, do: [], else: [{:speech_started, start_fields(canon, event)}]
      {transcript, last_text} = settle_transcript(canon, entry, event)
      marks = settle_marks(canon, entry, transcript, last_text)
      end_text = if nonempty?(event.text), do: event.text, else: last_text || event.text
      ended = [{:turn_ended, end_fields(canon, %{event | text: end_text})}]
      entry = %{entry | started: true, ended: true, last_text: last_text, marks: []}
      state = put_entry(state, canon, entry)
      state = if state.active == canon, do: %{state | active: nil}, else: state

      case drain(state) do
        {:ok, state, drained} -> {:ok, state, start ++ transcript ++ marks ++ ended ++ drained}
        {:error, _reason} = error -> error
      end
    end
  end

  defp settle_transcript(canon, entry, event) do
    if nonempty?(event.text) and event.text != entry.last_text do
      {[{:transcript, transcript_fields(canon, event.text, event.provider_request_id)}],
       event.text}
    else
      {[], entry.last_text}
    end
  end

  defp settle_marks(canon, entry, transcript, last_text) do
    if transcript == [] and is_nil(last_text) do
      []
    else
      Enum.map(entry.marks, &canonical_mark(canon, &1))
    end
  end

  defp activate_with_text(state, canon, text, provider_request_id) do
    entry = Map.fetch!(state.turns, canon)
    start = {:speech_started, [turn_ref: canon] ++ request_id_fields(provider_request_id)}
    transcript = {:transcript, transcript_fields(canon, text, provider_request_id)}
    marks = Enum.map(entry.marks, &canonical_mark(canon, &1))

    entry = %{
      entry
      | started: true,
        last_text: text,
        marks: [],
        pending_text: nil,
        pending_prid: nil,
        pending_end: nil
    }

    state = put_entry(state, canon, entry)
    {:ok, %{state | active: canon}, [start, transcript] ++ marks}
  end

  defp on_mark(state, canon, event) do
    entry = Map.fetch!(state.turns, canon)
    kind = mark_kind(event)

    cond do
      entry.ended ->
        {:ok, state, []}

      not is_nil(entry.pending_end) ->
        {:ok, state, []}

      kind == entry.last_mark ->
        {:ok, state, []}

      canon == state.active and entry.started and not is_nil(entry.last_text) ->
        state = put_entry(state, canon, %{entry | last_mark: kind})
        {:ok, state, [canonical_mark(canon, event)]}

      length(entry.marks) >= @max_controls ->
        {:error, :turn_overflow}

      true ->
        state = put_entry(state, canon, %{entry | marks: entry.marks ++ [event], last_mark: kind})
        {:ok, state, []}
    end
  end

  defp drain(%{active: active} = state) when not is_nil(active), do: {:ok, state, []}

  defp drain(state) do
    next =
      Enum.find(state.order, fn canon ->
        entry = Map.fetch!(state.turns, canon)
        not entry.ended and not is_nil(entry.pending_text)
      end)

    case next do
      nil -> {:ok, state, []}
      canon -> drain_one(state, canon)
    end
  end

  defp drain_one(state, canon) do
    entry = Map.fetch!(state.turns, canon)
    effective_prid = end_prid(entry.pending_end) || entry.pending_prid
    start = {:speech_started, [turn_ref: canon] ++ request_id_fields(effective_prid)}

    transcript =
      {:transcript, transcript_fields(canon, entry.pending_text, effective_prid)}

    marks = Enum.map(entry.marks, &canonical_mark(canon, &1))
    entry = %{entry | started: true, last_text: entry.pending_text, marks: []}

    case entry.pending_end do
      nil ->
        entry = %{entry | pending_text: nil, pending_prid: nil}
        state = put_entry(state, canon, entry)
        {:ok, %{state | active: canon}, [start, transcript] ++ marks}

      final ->
        with {:ok, state} <- add_retired(state, entry.native) do
          end_text =
            if nonempty?(final.text), do: final.text, else: entry.pending_text || final.text

          ended = {:turn_ended, end_fields(canon, %{final | text: end_text})}
          entry = %{entry | ended: true, pending_text: nil, pending_prid: nil, pending_end: nil}
          state = put_entry(state, canon, entry)

          case drain(state) do
            {:ok, state, rest} -> {:ok, state, [start, transcript] ++ marks ++ [ended] ++ rest}
            {:error, _reason} = error -> error
          end
        end
    end
  end

  defp silently_close(state, canon, native_ref) do
    with {:ok, state} <- add_retired(state, native_ref) do
      entry = Map.fetch!(state.turns, canon)
      {:ok, put_entry(state, canon, %{entry | ended: true}), []}
    end
  end

  defp correlate(state, native_ref) do
    case Map.fetch(state.native, native_ref) do
      {:ok, canon} ->
        {:ok, state, canon}

      :error ->
        case acoustic_unbound(state) do
          nil -> allocate(state, native_ref)
          canon -> {:ok, bind(state, native_ref, canon), canon}
        end
    end
  end

  defp acoustic_unbound(state) do
    case state.active do
      nil ->
        nil

      active ->
        entry = Map.fetch!(state.turns, active)

        if is_nil(entry.native) and entry.started and not entry.ended do
          active
        else
          nil
        end
    end
  end

  defp earliest_pending_hint(state) do
    Enum.find(state.order, fn canon ->
      entry = Map.fetch!(state.turns, canon)
      not entry.ended and not entry.started and not is_nil(entry.native)
    end)
  end

  defp bind(state, native_ref, canon) do
    entry = Map.fetch!(state.turns, canon)
    state = put_entry(state, canon, %{entry | native: native_ref})
    %{state | native: Map.put(state.native, native_ref, canon)}
  end

  defp allocate(state, native_ref) do
    with {:ok, state} <- ensure_room(state),
         {:ok, state} <- ensure_retired_room(state, native_ref) do
      canon = make_ref()

      entry = %{
        native: native_ref,
        started: false,
        ended: false,
        last_text: nil,
        marks: [],
        last_mark: nil,
        pending_text: nil,
        pending_prid: nil,
        pending_end: nil
      }

      state = %{state | turns: Map.put(state.turns, canon, entry), order: state.order ++ [canon]}

      state =
        if is_nil(native_ref),
          do: state,
          else: %{state | native: Map.put(state.native, native_ref, canon)}

      {:ok, state, canon}
    end
  end

  defp ensure_room(state) do
    if map_size(state.turns) < @max_turns do
      {:ok, state}
    else
      case Enum.find(state.order, fn canon ->
             entry = Map.fetch!(state.turns, canon)
             entry.ended
           end) do
        nil -> {:error, :turn_overflow}
        canon -> drop_turn(state, canon)
      end
    end
  end

  defp ensure_retired_room(state, nil), do: {:ok, state}

  defp ensure_retired_room(state, native_ref) do
    cond do
      retired?(state, native_ref) -> {:ok, state}
      MapSet.size(state.retired) >= @max_retired -> {:error, :turn_overflow}
      true -> {:ok, state}
    end
  end

  defp drop_turn(state, canon) do
    entry = Map.fetch!(state.turns, canon)

    with {:ok, state} <- add_retired(state, entry.native) do
      native =
        if is_nil(entry.native),
          do: state.native,
          else: Map.delete(state.native, entry.native)

      {:ok,
       %{
         state
         | turns: Map.delete(state.turns, canon),
           order: List.delete(state.order, canon),
           native: native
       }}
    end
  end

  defp add_retired(state, nil), do: {:ok, state}

  defp add_retired(state, native_ref) do
    cond do
      MapSet.member?(state.retired, native_ref) ->
        {:ok, state}

      MapSet.size(state.retired) >= @max_retired ->
        {:error, :turn_overflow}

      true ->
        {:ok, %{state | retired: MapSet.put(state.retired, native_ref)}}
    end
  end

  defp retired?(state, native_ref), do: MapSet.member?(state.retired, native_ref)

  defp put_entry(state, canon, entry), do: %{state | turns: Map.put(state.turns, canon, entry)}

  defp nonempty?(text), do: String.trim(text) != ""

  defp mark_kind(%Event{kind: :eager_turn_ended}), do: :eager_turn_ended
  defp mark_kind(%Event{kind: :turn_resumed}), do: :turn_resumed

  defp canonical_mark(canon, %Event{kind: :eager_turn_ended} = event) do
    {:eager_turn_ended,
     [turn_ref: canon, text: event.text, endpointing: event.endpointing] ++
       request_id_fields(event.provider_request_id) ++
       duration_fields(event.audio_duration_ms)}
  end

  defp canonical_mark(canon, %Event{kind: :turn_resumed} = event) do
    {:turn_resumed, [turn_ref: canon] ++ request_id_fields(event.provider_request_id)}
  end

  defp start_fields(canon, event) do
    [turn_ref: canon] ++ request_id_fields(event.provider_request_id)
  end

  defp transcript_fields(canon, text, provider_request_id) do
    [turn_ref: canon, text: text] ++ request_id_fields(provider_request_id)
  end

  defp end_fields(canon, event) do
    [turn_ref: canon, text: event.text, endpointing: event.endpointing] ++
      request_id_fields(event.provider_request_id) ++
      duration_fields(event.audio_duration_ms)
  end

  defp request_id_fields(provider_request_id) when is_binary(provider_request_id),
    do: [provider_request_id: provider_request_id]

  defp request_id_fields(_provider_request_id), do: []

  defp duration_fields(audio_duration_ms)
       when is_integer(audio_duration_ms) and audio_duration_ms >= 0,
       do: [audio_duration_ms: audio_duration_ms]

  defp duration_fields(_audio_duration_ms), do: []

  defp end_prid(nil), do: nil
  defp end_prid(event), do: event.provider_request_id
end
