defmodule Vxpipe.CallEngine.Diagnostics.TurnTiming do
  @moduledoc "Clock-scoped timing evidence for one human turn, independent of call control."

  @landmarks [
    :acoustic_end,
    :observer_confirmed,
    :provider_text_commit,
    :provider_end_received,
    :adapter_end_emitted,
    :room_turn_completed,
    :first_response_text,
    :first_audio_started,
    :manual_commit_sent
  ]
  @acoustic_reasons [
    :audio_gap,
    :ambiguous_boundary,
    :observer_overloaded,
    :source_changed,
    :partial_start,
    :inference_reset,
    :clock_uncertain,
    :observer_unavailable,
    :unsupported,
    :policy_denied
  ]
  @metrics [
    {:speech_end_to_provider_end, :acoustic_end, :provider_end_received},
    {:observer_confirmation, :acoustic_end, :observer_confirmed},
    {:commit_to_provider_end, :provider_text_commit, :provider_end_received},
    {:provider_to_adapter, :provider_end_received, :adapter_end_emitted},
    {:provider_to_room, :provider_end_received, :room_turn_completed},
    {:room_to_first_text, :room_turn_completed, :first_response_text},
    {:text_to_first_audio, :first_response_text, :first_audio_started},
    {:speech_end_to_first_audio, :acoustic_end, :first_audio_started},
    {:speech_end_to_manual_commit, :acoustic_end, :manual_commit_sent},
    {:manual_commit_to_provider_end, :manual_commit_sent, :provider_end_received}
  ]
  @maximum_offset_us 7 * 24 * 60 * 60 * 1_000_000

  @enforce_keys [:clock_id]
  @derive {Inspect, only: [:clock_id, :acoustic_reason]}
  defstruct [:clock_id, :acoustic_reason, landmarks_us: %{}]

  def new(clock_id) when is_binary(clock_id) and byte_size(clock_id) in 1..128,
    do: %__MODULE__{clock_id: clock_id}

  def observe(%__MODULE__{clock_id: expected}, _landmark, _offset_us, clock_id)
      when clock_id != expected,
      do: {:error, :clock_mismatch}

  def observe(%__MODULE__{} = timing, landmark, offset_us, _clock_id)
      when landmark in @landmarks and is_integer(offset_us) and
             offset_us >= 0 and offset_us <= @maximum_offset_us do
    landmarks =
      Map.update(timing.landmarks_us, landmark, offset_us, fn old ->
        if landmark in [:provider_text_commit, :manual_commit_sent],
          do: max(old, offset_us),
          else: min(old, offset_us)
      end)

    conflicting_endpoint? =
      landmark == :acoustic_end and
        Map.has_key?(timing.landmarks_us, landmark) and
        Map.fetch!(timing.landmarks_us, landmark) != offset_us

    reason = timing.acoustic_reason || if(conflicting_endpoint?, do: :ambiguous_boundary)
    {:ok, %{timing | landmarks_us: landmarks, acoustic_reason: reason}}
  end

  def observe(%__MODULE__{}, _landmark, _offset_us, _clock_id),
    do: {:error, :invalid_observation}

  def invalidate_acoustic(%__MODULE__{} = timing, reason) when reason in @acoustic_reasons,
    do: {:ok, %{timing | acoustic_reason: timing.acoustic_reason || reason}}

  def invalidate_acoustic(%__MODULE__{}, _reason), do: {:error, :invalid_reason}

  def report(%__MODULE__{} = timing) do
    {durations, reasons} =
      Enum.reduce(@metrics, {%{}, %{}}, fn {name, from, to}, {durations, reasons} ->
        {duration, reason} = duration(timing, from, to)
        {Map.put(durations, name, duration), Map.put(reasons, name, reason)}
      end)

    %{
      clock_id: timing.clock_id,
      landmarks_us: timing.landmarks_us,
      durations_us: durations,
      metric_reasons: reasons,
      acoustic_reason: timing.acoustic_reason,
      quality: quality(timing, durations)
    }
  end

  defp duration(%{acoustic_reason: reason}, :acoustic_end, _to) when not is_nil(reason),
    do: {nil, reason}

  defp duration(timing, from, to) do
    with {:ok, start} <- Map.fetch(timing.landmarks_us, from),
         {:ok, finish} <- Map.fetch(timing.landmarks_us, to) do
      if finish >= start and causal_order_valid?(timing, from, to),
        do: {finish - start, nil},
        else: {nil, :invalid_order}
    else
      :error -> {nil, :missing_evidence}
    end
  end

  defp causal_order_valid?(timing, from, to) do
    chain = [
      :provider_end_received,
      :adapter_end_emitted,
      :room_turn_completed,
      :first_response_text,
      :first_audio_started
    ]

    chain
    |> Enum.filter(&Map.has_key?(timing.landmarks_us, &1))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] ->
      ordered? = Map.fetch!(timing.landmarks_us, left) <= Map.fetch!(timing.landmarks_us, right)
      ordered? or (from not in [left, right] and to not in [left, right])
    end)
  end

  defp quality(_timing, %{speech_end_to_provider_end: value}) when is_integer(value),
    do: :available

  defp quality(%{landmarks_us: landmarks}, _durations) when map_size(landmarks) == 0,
    do: :unavailable

  defp quality(_timing, _durations), do: :incomplete
end
