defmodule Vxpipe.CallEngine.Speech.Duplex.BurstResponses do
  @moduledoc """
  Maps contiguous output bursts to provider-initiated responses.

  A GPT-Live-style provider streams one continuous output timeline with no
  knowledge of where a reply starts or ends. `Speech.Duplex.OutputSegmenter`
  splits that timeline into audible bursts. This pure module owns the mapping
  from each burst to its own `:response_started` announcement, its admission,
  its completion and its transcript turn.

  The provider performs all I/O: it emits `:response_started`, calls
  `OutputSegmenter.admitted/2`, forwards credited audio and emits
  `:output_completed`. Every function returns `{burst_responses, actions}` and
  performs no side effects, so the real OpenAI adapter can reuse it unchanged.
  """

  @default_maximum_unadmitted 4

  @enforce_keys [:maximum_unadmitted]
  defstruct [
    :maximum_unadmitted,
    latest_context: nil,
    last_index: 0,
    bursts: %{},
    order: []
  ]

  @type burst_state :: :announced | :admitted | :discarded | :completed

  @type burst :: %{
          turn_ref: reference(),
          index: pos_integer(),
          context: reference(),
          seg_ref: reference(),
          state: burst_state(),
          output_ref: reference() | nil,
          yielded?: boolean(),
          closed?: boolean()
        }

  @type action ::
          {:announce, reference(), pos_integer(), reference()}
          | {:admit_segment, reference(), reference()}
          | {:complete, reference(), reference()}
          | {:complete_empty, reference(), reference()}
          | {:drop_segment, reference()}

  @type t :: %__MODULE__{}

  @doc "Build burst-response state. `maximum_unadmitted` defaults to 4."
  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options \\ [])

  def new(options) when is_list(options) do
    maximum = Keyword.get(options, :maximum_unadmitted, @default_maximum_unadmitted)

    if Keyword.keyword?(options) and is_integer(maximum) and maximum > 0 do
      {:ok, %__MODULE__{maximum_unadmitted: maximum}}
    else
      {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  @doc "Record the context of a newly accepted input as the latest origin."
  @spec input_accepted(t(), reference()) :: {t(), []}
  def input_accepted(%__MODULE__{} = state, context) when is_reference(context),
    do: {%{state | latest_context: context}, []}

  def input_accepted(%__MODULE__{} = state, _context), do: {state, []}

  @doc """
  Open a burst. Announces a fresh response when a context is known, drops the
  segment when no input was ever accepted, and fails explicitly beyond the
  unadmitted bound.
  """
  @spec burst_opened(t(), reference()) ::
          {t(), [action()]} | {:error, :pending_response_overflow}
  def burst_opened(%__MODULE__{} = state, seg_ref) when is_reference(seg_ref) do
    cond do
      is_nil(state.latest_context) ->
        {state, [{:drop_segment, seg_ref}]}

      unadmitted(state) >= state.maximum_unadmitted ->
        {:error, :pending_response_overflow}

      true ->
        announce(state, seg_ref)
    end
  end

  @doc "Confirm admission of an announced burst; may admit and immediately complete."
  @spec admitted(t(), reference(), reference()) :: {t(), [action()]}
  def admitted(%__MODULE__{} = state, turn_ref, output_ref)
      when is_reference(turn_ref) and is_reference(output_ref) do
    case Map.fetch(state.bursts, turn_ref) do
      {:ok, %{state: :announced} = burst} ->
        admitted(state, %{burst | output_ref: output_ref})

      _other ->
        {state, []}
    end
  end

  def admitted(%__MODULE__{} = state, _turn_ref, _output_ref), do: {state, []}

  @doc "Discard a burst the room rejected. Nothing is played and nothing completes."
  @spec discarded(t(), reference()) :: {t(), [action()]}
  def discarded(%__MODULE__{} = state, turn_ref) when is_reference(turn_ref) do
    case Map.fetch(state.bursts, turn_ref) do
      {:ok, %{state: :announced} = burst} ->
        {put(state, %{burst | state: :discarded}), [{:drop_segment, burst.seg_ref}]}

      _other ->
        {state, []}
    end
  end

  def discarded(%__MODULE__{} = state, _turn_ref), do: {state, []}

  @doc """
  Close a burst. An admitted burst completes; an announced one is marked closed
  and completes when its admission arrives.
  """
  @spec burst_closed(t(), reference()) :: {t(), [action()]}
  def burst_closed(%__MODULE__{} = state, seg_ref) when is_reference(seg_ref) do
    case find_segment(state, seg_ref) do
      {:ok, %{state: :admitted, output_ref: output_ref} = burst} ->
        {put(state, %{burst | state: :completed}), [{:complete, burst.turn_ref, output_ref}]}

      {:ok, %{state: :announced} = burst} ->
        {put(state, %{burst | closed?: true}), []}

      _other ->
        {state, []}
    end
  end

  def burst_closed(%__MODULE__{} = state, _seg_ref), do: {state, []}

  @doc "Mark the newest open burst yielded, so it completes empty if it is admitted."
  @spec yielded(t()) :: {t(), []}
  def yielded(%__MODULE__{} = state) do
    case newest_open(state) do
      {:ok, burst} -> {put(state, %{burst | yielded?: true}), []}
      :error -> {state, []}
    end
  end

  @doc "The latest accepted input context, or nil before any input."
  @spec latest_context(t()) :: reference() | nil
  def latest_context(%__MODULE__{latest_context: context}), do: context

  @doc "The turn reference for one segment, for attaching transcript fragments."
  @spec turn_for_segment(t(), reference()) :: {:ok, reference()} | :error
  def turn_for_segment(%__MODULE__{} = state, seg_ref) when is_reference(seg_ref) do
    case find_segment(state, seg_ref) do
      {:ok, burst} -> {:ok, burst.turn_ref}
      :error -> :error
    end
  end

  def turn_for_segment(%__MODULE__{}, _seg_ref), do: :error

  defp announce(state, seg_ref) do
    index = state.last_index + 1
    turn_ref = make_ref()

    burst = %{
      turn_ref: turn_ref,
      index: index,
      context: state.latest_context,
      seg_ref: seg_ref,
      state: :announced,
      output_ref: nil,
      yielded?: false,
      closed?: false
    }

    state = %{
      state
      | last_index: index,
        bursts: Map.put(state.bursts, turn_ref, burst),
        order: state.order ++ [turn_ref]
    }

    {state, [{:announce, turn_ref, index, burst.context}]}
  end

  defp admitted(state, burst) do
    cond do
      burst.yielded? ->
        {put(state, %{burst | state: :completed}),
         [{:complete_empty, burst.turn_ref, burst.output_ref}]}

      burst.closed? ->
        {put(state, %{burst | state: :completed}),
         [
           {:admit_segment, burst.seg_ref, burst.output_ref},
           {:complete, burst.turn_ref, burst.output_ref}
         ]}

      true ->
        {put(state, %{burst | state: :admitted}),
         [{:admit_segment, burst.seg_ref, burst.output_ref}]}
    end
  end

  defp unadmitted(state) do
    Enum.count(state.bursts, fn {_turn, burst} -> burst.state == :announced end)
  end

  defp newest_open(state) do
    state.order
    |> Enum.reverse()
    |> Enum.find_value(:error, fn turn_ref ->
      case Map.fetch(state.bursts, turn_ref) do
        {:ok, %{state: open} = burst} when open in [:announced, :admitted] -> {:ok, burst}
        _other -> nil
      end
    end)
  end

  defp find_segment(state, seg_ref) do
    Enum.find_value(state.order, :error, fn turn_ref ->
      case Map.fetch(state.bursts, turn_ref) do
        {:ok, %{seg_ref: ^seg_ref} = burst} -> {:ok, burst}
        _other -> nil
      end
    end)
  end

  defp put(state, burst), do: %{state | bursts: Map.put(state.bursts, burst.turn_ref, burst)}
end
