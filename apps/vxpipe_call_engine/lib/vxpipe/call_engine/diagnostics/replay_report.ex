defmodule Vxpipe.CallEngine.Diagnostics.ReplayReport do
  @moduledoc "Correlates one source's offline acoustic boundaries with actual replayed provider turns."
  alias Vxpipe.CallEngine.Diagnostics.TurnTiming

  @provider_landmarks [
    :provider_text_commit,
    :provider_end_received,
    :adapter_end_emitted,
    :room_turn_completed,
    :first_response_text,
    :first_audio_started,
    :manual_commit_sent
  ]
  @notices [:audio_gap, :partial_start, :observer_overloaded, :source_changed]

  def build(clock_id, source_epoch, turns, %{events: events, notices: notices})
      when is_list(turns) and length(turns) <= 1_000 and is_list(events) and
             length(events) <= 10_000 and is_list(notices) and length(notices) <= 10 do
    with true <- Enum.all?(events, &valid_event?(&1, clock_id, source_epoch)),
         true <- Enum.all?(notices, &(&1 in @notices)) do
      turns
      |> Enum.reduce_while({:ok, [], -1}, fn landmarks, {:ok, reports, previous} ->
        with {:ok, timing} <- provider_timing(clock_id, landmarks),
             finish = Map.get(landmarks, :provider_end_received),
             true <- finish == nil or finish >= previous do
          {timing, endpoint} = attach(timing, events, notices, previous, finish)

          report =
            TurnTiming.report(timing)
            |> Map.merge(%{
              acoustic_sample: if(endpoint, do: endpoint.sample),
              uncertainty_us: if(endpoint, do: endpoint.uncertainty_us)
            })

          {:cont, {:ok, [report | reports], finish || previous}}
        else
          _invalid -> {:halt, {:error, :invalid_replay_evidence}}
        end
      end)
      |> case do
        {:ok, reports, _previous} -> {:ok, Enum.reverse(reports)}
        error -> error
      end
    else
      _invalid -> {:error, :invalid_replay_evidence}
    end
  end

  def build(_clock, _source, _turns, _trace), do: {:error, :invalid_replay_evidence}

  defp provider_timing(clock_id, landmarks)
       when is_map(landmarks) and not is_struct(landmarks) and map_size(landmarks) <= 7 do
    Enum.reduce_while(landmarks, {:ok, TurnTiming.new(clock_id)}, fn {kind, offset},
                                                                     {:ok, timing} ->
      if kind in @provider_landmarks do
        case TurnTiming.observe(timing, kind, offset, clock_id) do
          {:ok, next} -> {:cont, {:ok, next}}
          error -> {:halt, error}
        end
      else
        {:halt, {:error, :invalid_replay_evidence}}
      end
    end)
  end

  defp provider_timing(_clock, _landmarks), do: {:error, :invalid_replay_evidence}

  defp attach(timing, _events, [reason | _], _previous, _finish),
    do: {invalidate(timing, reason), nil}

  defp attach(timing, _events, _notices, _previous, nil), do: {timing, nil}

  defp attach(timing, events, [], previous, finish) do
    ends =
      for {:speech_ended, position} <- events,
          position.offset_us > previous and position.offset_us <= finish,
          do: position

    endpoint = Enum.max_by(ends, & &1.offset_us, fn -> nil end)

    resumed? =
      endpoint != nil and
        Enum.any?(events, fn
          {:speech_started, position} ->
            position.offset_us > endpoint.offset_us and position.offset_us <= finish

          _event ->
            false
        end)

    cond do
      Enum.any?(events, &match?({:unmapped_boundary, _, _, _}, &1)) ->
        {invalidate(timing, :observer_unavailable), nil}

      resumed? ->
        {invalidate(timing, :ambiguous_boundary), nil}

      endpoint == nil ->
        {timing, nil}

      true ->
        {:ok, timing} =
          TurnTiming.observe(timing, :acoustic_end, endpoint.offset_us, timing.clock_id)

        {:ok, timing} =
          TurnTiming.observe(
            timing,
            :observer_confirmed,
            endpoint.confirmed_offset_us,
            timing.clock_id
          )

        {timing, endpoint}
    end
  end

  defp invalidate(timing, reason) do
    {:ok, timing} = TurnTiming.invalidate_acoustic(timing, reason)
    timing
  end

  defp valid_event?({kind, position}, clock_id, source_epoch)
       when kind in [:speech_started, :speech_ended] and is_map(position) do
    position[:clock_id] == clock_id and position[:source_epoch] == source_epoch and
      bounded?(position[:offset_us]) and bounded?(position[:confirmed_offset_us]) and
      position[:confirmed_offset_us] >= position[:offset_us] and
      bounded?(position[:uncertainty_us]) and
      is_integer(position[:sample]) and position[:sample] >= 0 and
      position[:sample] <= 9_223_372_036_854_775_807
  end

  defp valid_event?({:unmapped_boundary, kind, sample, reason}, _clock, _source),
    do:
      kind in [:speech_started, :speech_ended] and is_integer(sample) and sample >= 0 and
        reason in [:unobserved_audio, :before_run, :clock_uncertain, :invalid_sample]

  defp valid_event?(_event, _clock, _source), do: false
  defp bounded?(value), do: is_integer(value) and value in 0..604_800_000_000
end
