defmodule Vxpipe.CallEngine.Diagnostics.SegmentProjection do
  @moduledoc "Projects bounded acoustic segments onto proven canonical source intervals."

  @limit 32

  def valid_order?(packets) do
    packets
    |> Enum.filter(&match?({:acoustic_boundary, _, _, _, _, _, _, _}, &1))
    |> Enum.group_by(&elem(&1, 1))
    |> Enum.all?(fn {_epoch, boundaries} ->
      ordered =
        Enum.sort_by(boundaries, &{elem(&1, 3), elem(&1, 5), elem(&1, 2) == :speech_started})

      alternating?(ordered) and monotonic?(Enum.map(ordered, &elem(&1, 5))) and
        monotonic?(ordered |> Enum.map(&elem(&1, 4)) |> Enum.reject(&is_nil/1))
    end)
  end

  defp alternating?(boundaries) do
    boundaries
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> elem(a, 2) != elem(b, 2) end)
  end

  defp monotonic?(values),
    do: values |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a <= b end)

  def build(packets, intervals, closed_epochs) do
    observed? =
      Enum.any?(packets, fn
        {:acoustic_boundary, _, _, _, _, _, _, _} -> true
        {:acoustic_progress, _, _, _} -> true
        _ -> false
      end)

    if observed? do
      project(packets, intervals, closed_epochs)
    else
      {Map.new(intervals, fn {key, _} -> {key, nil} end), nil}
    end
  end

  defp project(packets, intervals, closed_epochs) do
    segments =
      packets
      |> Enum.filter(&match?({:acoustic_boundary, _, _, _, _, _, _, _}, &1))
      |> Enum.group_by(&elem(&1, 1))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {epoch, boundaries} ->
        pair(epoch, boundaries, packets, closed_epochs)
      end)

    grouped =
      segments
      |> Enum.map(fn segment ->
        case owner(segment, intervals) do
          :ambiguous ->
            {nil, %{segment | reasons: Enum.uniq([:ambiguous_boundary | segment.reasons])}}

          key ->
            {key, segment}
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    attached =
      Map.new(intervals, fn {key, bounds} ->
        evidence = envelope(Map.get(grouped, key, []))

        evidence = %{
          evidence
          | reasons:
              Enum.uniq(coverage_reasons(bounds, packets, closed_epochs) ++ evidence.reasons)
        }

        {key, evidence}
      end)

    {attached, envelope(Map.get(grouped, nil, []))}
  end

  defp pair(epoch, boundaries, packets, closed_epochs) do
    groups =
      boundaries
      |> Enum.sort_by(&{elem(&1, 3), elem(&1, 5), elem(&1, 2) == :speech_started})
      |> Enum.chunk_by(&elem(&1, 2))

    pair_groups(epoch, groups, packets, closed_epochs)
  end

  defp pair_groups(_epoch, [], _packets, _closed_epochs), do: []

  defp pair_groups(epoch, [starts, ends | rest], packets, closed_epochs)
       when elem(hd(starts), 2) == :speech_started do
    [
      segment(epoch, starts, ends, packets, closed_epochs)
      | pair_groups(epoch, rest, packets, closed_epochs)
    ]
  end

  defp pair_groups(epoch, [group | rest], packets, closed_epochs) do
    segment =
      if elem(hd(group), 2) == :speech_started,
        do: segment(epoch, group, [], packets, closed_epochs),
        else: segment(epoch, [], group, packets, closed_epochs)

    [segment | pair_groups(epoch, rest, packets, closed_epochs)]
  end

  defp segment(epoch, starts, ends, packets, closed_epochs) do
    start = List.first(starts)
    finish = List.last(ends)
    boundaries = Enum.reject([start, finish], &is_nil/1)
    reasons = Enum.flat_map(boundaries, &boundary_reasons/1)
    reasons = if start == nil, do: [:partial_start | reasons], else: reasons

    reasons =
      if finish == nil,
        do: [closing_reason(epoch, packets, closed_epochs) | reasons],
        else: reasons

    reasons =
      if length(starts) > 1 or length(ends) > 1,
        do: [:ambiguous_boundary | reasons],
        else: reasons

    %{
      epoch: epoch,
      start_sample: field(start, 3),
      end_sample: field(finish, 3),
      start_us: field(start, 4),
      end_us: field(finish, 4),
      start_confirmed_us: field(start, 5),
      end_confirmed_us: field(finish, 5),
      uncertainty_us: uncertainty(boundaries),
      reasons: Enum.uniq(reasons)
    }
  end

  defp field(nil, _index), do: nil
  defp field(boundary, index), do: elem(boundary, index)

  defp uncertainty(boundaries) do
    values = Enum.map(boundaries, &elem(&1, 6))
    if Enum.any?(values, &is_nil/1), do: nil, else: Enum.max(values)
  end

  defp boundary_reasons(boundary) do
    case elem(boundary, 7) do
      nil -> []
      :partial_start -> [:partial_start]
      _ -> [:clock_uncertain]
    end
  end

  defp closing_reason(epoch, packets, closed_epochs) do
    Map.get_lazy(closed_epochs, epoch, fn ->
      packets
      |> Enum.filter(fn
        {:reset, next, _, _} -> next > epoch
        _ -> false
      end)
      |> Enum.min_by(&elem(&1, 1), fn -> nil end)
      |> case do
        nil -> :pending
        {:reset, _, :audio_gap, _} -> :audio_gap
        {:reset, _, :source_replaced, _} -> :source_changed
        {:reset, _, _, _} -> :inference_reset
      end
    end)
  end

  defp coverage_reasons({left, right} = bounds, packets, closed_epochs)
       when is_integer(left) and is_integer(right) do
    if covered?(bounds, packets) do
      []
    else
      epochs =
        Enum.flat_map(packets, fn
          {:acoustic_progress, epoch, origin, finalized}
          when origin < right and finalized > left ->
            [epoch]

          {:acoustic_boundary, epoch, kind, sample, _, _, _, _}
          when (sample > left or (sample == left and kind == :speech_started)) and
                 (sample < right or (sample == right and kind == :speech_ended)) ->
            [epoch]

          _ ->
            []
        end)

      reasons =
        epochs
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&Map.get(closed_epochs, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      if reasons == [], do: [:pending], else: reasons
    end
  end

  defp coverage_reasons(_, _, _), do: [:pending]

  defp covered?({left, right}, packets) when is_integer(left) and is_integer(right) do
    Enum.any?(packets, fn
      {:acoustic_progress, _, origin, finalized} -> origin <= left and finalized >= right
      _ -> false
    end)
  end

  defp covered?(_, _), do: false

  defp owner(%{start_sample: start, end_sample: finish}, intervals)
       when is_integer(start) and is_integer(finish) do
    matches =
      for {key, {left, right}} <- intervals,
          is_integer(left) and is_integer(right) and left <= start and start < right and
            left < finish and finish <= right,
          do: key

    case matches do
      [key] -> key
      [] -> nil
      _ -> :ambiguous
    end
  end

  defp owner(_, _), do: nil

  defp envelope(segments) do
    omitted = max(length(segments) - @limit, 0)

    %{
      version: 1,
      entries: Enum.take(segments, @limit),
      omitted_count: omitted,
      reasons: if(omitted > 0, do: [:segment_limit], else: [])
    }
  end
end
