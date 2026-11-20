defmodule Vxpipe.CallEngine.Diagnostics.LiveReport do
  @moduledoc "Bounded source-run evidence joined by provider, canonical turn and command identity."
  alias Vxpipe.CallEngine.Diagnostics.{CapturePacket, SegmentProjection, TurnTiming}

  @provider_kinds %{
    provider_text_commit: :provider_text_commit,
    manual_commit_sent: :manual_commit_sent,
    provider_end_evidence: :provider_end_received,
    adapter_end_emission: :adapter_end_emitted
  }
  @enforce_keys [:generation, :clock_id, :origin_us, :maximum_packets, :maximum_bytes]
  @derive {Inspect, only: [:maximum_packets, :maximum_bytes]}
  defstruct @enforce_keys ++
              [packets: %{}, reports: %{}, closed_epochs: %{}, unattached_segments: nil]

  def new(context, options \\ []) do
    %__MODULE__{
      generation: context.generation,
      clock_id: context.clock_id,
      origin_us: context.origin_us,
      maximum_packets: bounded!(options, :maximum_packets, 1_024, 1..4_096),
      maximum_bytes: bounded!(options, :maximum_bytes, 1_048_576, 1..4_194_304)
    }
  end

  def observe(state, packet) do
    with {:ok, _} <- CapturePacket.charge(packet),
         packet = CapturePacket.copy(packet),
         {:ok, key} <- key(packet),
         :ok <- generation(state, packet),
         :ok <- unique_room(state, packet),
         :ok <- unique_link(state, packet),
         :ok <- current_progress(state, packet),
         {:ok, packet} <- merge(Map.get(state.packets, key), packet),
         packets = Map.put(state.packets, key, CapturePacket.copy(packet)),
         true <- map_size(packets) <= state.maximum_packets,
         :ok <- segment_order(packets),
         next = %{state | packets: packets},
         next = if(Map.has_key?(state.packets, key), do: next, else: close_epochs(next, packet)),
         {reports, unattached} = build_after(state, next, packet),
         next = %{next | reports: reports, unattached_segments: unattached},
         true <-
           4 *
             :erlang.external_size(
               {next.packets, next.reports, next.closed_epochs, next.unattached_segments}
             ) + 512 <=
             state.maximum_bytes do
      {:ok, next}
    else
      false -> {:error, :full}
      error -> error
    end
  end

  defp segment_order(packets) do
    if SegmentProjection.valid_order?(Map.values(packets)),
      do: :ok,
      else: {:error, :conflicting_evidence}
  end

  def reports(state), do: state.reports |> Map.values() |> Enum.sort_by(& &1.turn_id)

  def unattached_segments(state), do: state.unattached_segments

  def project_segments(state, intervals),
    do: SegmentProjection.build(Map.values(state.packets), intervals, state.closed_epochs)

  def counts(state) do
    matched = MapSet.new(state.reports, fn {_key, report} -> report.provider_turn_id end)

    unmatched =
      Enum.count(state.packets, fn
        {{:provider, generation, reference, _kind}, _packet} ->
          not MapSet.member?(matched, identifier({generation, reference}))

        _ ->
          false
      end)

    %{observed_turns: map_size(state.reports), unmatched_provider_events: unmatched}
  end

  defp key({:provider_sample_mapping, generation, _, _}), do: {:ok, {:mapping, generation}}

  defp key({:provider_landmark, generation, turn, kind, _, _}),
    do: {:ok, {:provider, generation, turn, kind}}

  defp key({:turn_link, generation, turn, _, _}), do: {:ok, {:link, generation, turn}}

  defp key({:room_turn_completed, generation, turn, _, _, _}),
    do: {:ok, {:room, generation, turn}}

  defp key({:response_landmark, turn, command, _, kind, _}),
    do: {:ok, {:response, turn, command, kind}}

  defp key({:acoustic_boundary, epoch, kind, sample, _, _, _, _}),
    do: {:ok, {:acoustic, epoch, kind, sample}}

  defp key({:acoustic_progress, epoch, _, _}), do: {:ok, {:progress, epoch}}

  defp key({:reset, epoch, reason, at}), do: {:ok, {:reset, epoch, reason, at}}
  defp key(_), do: {:error, :invalid_evidence}

  defp generation(state, {:room_turn_completed, generation, _, _, _, _}),
    do: expected_generation(state, generation)

  defp generation(state, {:turn_link, _, _, generation, _}),
    do: expected_generation(state, generation)

  defp generation(_state, _), do: :ok
  defp expected_generation(%{generation: generation}, generation), do: :ok
  defp expected_generation(_, _), do: {:error, :foreign_generation}

  defp unique_room(state, {:room_turn_completed, generation, reference, turn, command, _}) do
    collision? =
      Enum.any?(state.packets, fn
        {{:room, g, r}, {:room_turn_completed, _, _, old_turn, old_command, _}} ->
          {g, r} != {generation, reference} and (old_turn == turn or old_command == command)

        _ ->
          false
      end)

    if collision?, do: {:error, :conflicting_evidence}, else: :ok
  end

  defp unique_room(_state, _packet), do: :ok

  defp unique_link(state, {:turn_link, g, t, target_g, target_t}) do
    if {g, t} != {target_g, target_t} and Map.has_key?(state.packets, {:room, g, t}),
      do: {:error, :conflicting_evidence},
      else: :ok
  end

  defp unique_link(state, {:room_turn_completed, g, t, _, _, _}) do
    case Map.get(state.packets, {:link, g, t}) do
      {:turn_link, ^g, ^t, target_g, target_t} when {g, t} != {target_g, target_t} ->
        {:error, :conflicting_evidence}

      _ ->
        :ok
    end
  end

  defp unique_link(_state, _packet), do: :ok

  defp merge(nil, packet), do: {:ok, packet}
  defp merge(packet, packet), do: {:ok, packet}

  defp merge(
         {:provider_landmark, g, t, k, old, old_samples},
         {:provider_landmark, g, t, k, at, samples}
       ) do
    if k in [:provider_text_commit, :manual_commit_sent] do
      {:ok, {:provider_landmark, g, t, k, max(old, at), max(old_samples, samples)}}
    else
      {:error, :conflicting_evidence}
    end
  end

  defp merge({:acoustic_progress, epoch, origin, old}, {:acoustic_progress, epoch, origin, new}),
    do: {:ok, {:acoustic_progress, epoch, origin, max(old, new)}}

  defp merge(_, _), do: {:error, :conflicting_evidence}

  defp build_after(state, next, {:acoustic_progress, epoch, origin, finalized}) do
    case Map.get(state.packets, {:progress, epoch}) do
      {:acoustic_progress, ^epoch, ^origin, previous} ->
        # With an unchanged epoch/origin, existing reports only change when
        # progress reaches a mapped provider end. Always retain the new cursor:
        # later events and caller-supplied segment intervals still need it.
        if crosses_provider_end?(state, previous, finalized),
          do: build(next),
          else: {state.reports, state.unattached_segments}

      _ ->
        build(next)
    end
  end

  defp build_after(_state, next, _packet), do: build(next)

  defp crosses_provider_end?(state, previous, finalized) do
    Enum.any?(state.packets, fn
      {_, {:provider_landmark, generation, _, :provider_end_evidence, _, samples}} ->
        case Map.get(state.packets, {:mapping, generation}) do
          {:provider_sample_mapping, ^generation, provider_origin, source_origin}
          when samples >= provider_origin ->
            source_end = source_origin + samples - provider_origin
            previous < source_end and source_end <= finalized

          _ ->
            false
        end

      _ ->
        false
    end)
  end

  defp build(state) do
    packets = Map.values(state.packets)
    rooms = for {:room_turn_completed, _, _, _, _, _} = room <- packets, do: room
    rows = Enum.map(rooms, &provider_row(state, packets, &1))

    ends =
      for {:provider_landmark, _, _, :provider_end_evidence, at, _} <- packets,
          at >= state.origin_us,
          do: at - state.origin_us

    intervals =
      Map.new(rows, fn
        {{:room_turn_completed, generation, reference, _, _, _}, _, ids} ->
          {{generation, reference}, segment_bounds(ids, packets)}
      end)

    {segments, unattached} = project_segments(state, intervals)

    reports =
      Map.new(rows, fn {room, timing, provider_ids} ->
        {:room_turn_completed, generation, reference, turn, command, _} = room
        finish = timing.landmarks_us[:provider_end_received]
        previous = Enum.filter(ends, &(finish != nil and &1 < finish)) |> Enum.max(fn -> -1 end)

        {timing, endpoint} =
          acoustic(
            state,
            timing,
            packets,
            previous,
            finish,
            source_bounds(provider_ids, packets, previous + state.origin_us)
          )

        timing =
          if length(provider_ids) > 1 or (finish != nil and Enum.count(ends, &(&1 == finish)) > 1),
            do: elem(TurnTiming.invalidate_acoustic(timing, :ambiguous_boundary), 1),
            else: timing

        timing = validate_coverage(timing, endpoint, provider_ids, packets)

        {timing, endpoint} =
          finalize_coverage(timing, endpoint, provider_ids, packets, state.closed_epochs)

        report =
          timing
          |> TurnTiming.report()
          |> Map.merge(%{
            acoustic_segments: Map.fetch!(segments, {generation, reference}),
            turn_id: turn,
            stt_allocation_id: identifier(generation),
            provider_turn_id: if(length(provider_ids) == 1, do: identifier(hd(provider_ids))),
            response_turn_id:
              if(
                Map.has_key?(timing.landmarks_us, :first_response_text) or
                  Map.has_key?(timing.landmarks_us, :first_audio_started),
                do: command
              ),
            acoustic_sample: if(endpoint, do: elem(endpoint, 3)),
            uncertainty_us: if(endpoint, do: elem(endpoint, 6))
          })

        key = {generation, reference}
        old = Map.get(state.reports, key)

        revision =
          cond do
            old == nil -> 1
            Map.delete(old, :revision) == report -> old.revision
            true -> old.revision + 1
          end

        {key, Map.put(report, :revision, revision)}
      end)

    {reports, unattached}
  end

  defp provider_row(
         state,
         packets,
         {:room_turn_completed, generation, reference, turn, command, at} = room
       ) do
    canonical = {generation, reference}
    providers = for {:turn_link, g, t, ^generation, ^reference} <- packets, do: {g, t}
    providers = Enum.uniq([canonical | providers])

    timing =
      observe_time(TurnTiming.new(state.clock_id), :room_turn_completed, at - state.origin_us)

    {timing, ids} =
      Enum.reduce(packets, {timing, []}, fn
        {:provider_landmark, g, t, kind, time, _samples}, {timing, ids} ->
          if {g, t} in providers do
            {observe_time(timing, Map.fetch!(@provider_kinds, kind), time - state.origin_us),
             Enum.uniq([{g, t} | ids])}
          else
            {timing, ids}
          end

        {:response_landmark, ^turn, ^command, _, kind, time}, {timing, ids} ->
          landmark = if kind == :first_audio_start, do: :first_audio_started, else: kind
          {observe_time(timing, landmark, time - state.origin_us), ids}

        _, acc ->
          acc
      end)

    timing =
      if length(ids) > 1 do
        %{timing | landmarks_us: Map.drop(timing.landmarks_us, Map.values(@provider_kinds))}
      else
        timing
      end

    {room, timing, ids}
  end

  defp acoustic(_state, timing, _packets, _previous, nil, _source_end), do: {timing, nil}

  defp acoustic(state, timing, packets, previous, finish, source_end) do
    boundaries =
      for {:acoustic_boundary, _, _, _, offset, _, _, _} = packet <- packets,
          is_integer(offset) and offset > previous and offset <= finish,
          within_source?(packet, source_end),
          do: packet

    endpoint =
      boundaries
      |> Enum.filter(&(elem(&1, 2) == :speech_ended))
      |> Enum.max_by(&elem(&1, 4), fn -> nil end)

    resets =
      for {:reset, _, reason, at} <- packets,
          at - state.origin_us > previous and at - state.origin_us <= finish,
          do: reason

    scoped_packets =
      Enum.reject(packets, fn
        {:acoustic_boundary, _, _, _, _, _, _, _} = packet ->
          not within_source?(packet, source_end)

        _ ->
          false
      end)

    reason = acoustic_reason(scoped_packets, boundaries, endpoint, resets, previous, finish)
    timing = if reason, do: elem(TurnTiming.invalidate_acoustic(timing, reason), 1), else: timing

    if endpoint do
      timing =
        timing
        |> observe_time(:acoustic_end, elem(endpoint, 4))
        |> observe_time(:observer_confirmed, elem(endpoint, 5))

      {timing, endpoint}
    else
      {timing, nil}
    end
  end

  defp acoustic_reason(_packets, _boundaries, _endpoint, [_ | _] = resets, _previous, _finish) do
    cond do
      :audio_gap in resets -> :audio_gap
      :partial_start in resets -> :partial_start
      :source_replaced in resets -> :source_changed
      true -> :inference_reset
    end
  end

  defp acoustic_reason(packets, boundaries, endpoint, [], previous, _finish) do
    cond do
      Enum.any?(packets, fn
        {:acoustic_boundary, _, _, _, nil, confirmed, _, _} ->
          confirmed > previous

        _ ->
          false
      end) ->
        :clock_uncertain

      endpoint == nil ->
        nil

      elem(endpoint, 7) != nil ->
        boundary_reason(elem(endpoint, 7))

      Enum.any?(boundaries, &(elem(&1, 2) == :speech_started and elem(&1, 4) > elem(endpoint, 4))) ->
        :ambiguous_boundary

      not Enum.any?(
        boundaries,
        &(elem(&1, 2) == :speech_started and elem(&1, 1) == elem(endpoint, 1) and
              elem(&1, 4) <= elem(endpoint, 4))
      ) ->
        :partial_start

      true ->
        nil
    end
  end

  defp validate_coverage(timing, nil, _ids, _packets), do: timing

  defp validate_coverage(timing, endpoint, [{g, t}], packets) do
    mapping = Enum.find(packets, &match?({:provider_sample_mapping, ^g, _, _}, &1))

    provider =
      Enum.find(packets, &match?({:provider_landmark, ^g, ^t, :provider_end_evidence, _, _}, &1))

    case {mapping, provider} do
      {{:provider_sample_mapping, ^g, provider_origin, source_origin},
       {:provider_landmark, ^g, ^t, _, _, samples}} ->
        source_end = source_origin + samples - provider_origin

        if samples >= provider_origin and elem(endpoint, 3) >= source_origin and
             elem(endpoint, 3) <= source_end,
           do: timing,
           else: elem(TurnTiming.invalidate_acoustic(timing, :clock_uncertain), 1)

      _ ->
        elem(TurnTiming.invalidate_acoustic(timing, :clock_uncertain), 1)
    end
  end

  defp validate_coverage(timing, _endpoint, _ids, _packets),
    do: elem(TurnTiming.invalidate_acoustic(timing, :ambiguous_boundary), 1)

  defp finalize_coverage(timing, nil, _ids, _packets, _closed), do: {timing, nil}

  defp finalize_coverage(timing, endpoint, [{g, t}], packets, closed) do
    mapping = Enum.find(packets, &match?({:provider_sample_mapping, ^g, _, _}, &1))

    provider =
      Enum.find(packets, &match?({:provider_landmark, ^g, ^t, :provider_end_evidence, _, _}, &1))

    epoch = elem(endpoint, 1)
    progress = Enum.find(packets, &match?({:acoustic_progress, ^epoch, _, _}, &1))

    covered? =
      case {mapping, provider, progress} do
        {{:provider_sample_mapping, ^g, provider_origin, source_origin},
         {:provider_landmark, ^g, ^t, _, _, samples},
         {:acoustic_progress, ^epoch, origin, finalized}} ->
          source_end = source_origin + samples - provider_origin

          samples >= provider_origin and origin <= elem(endpoint, 3) and
            elem(endpoint, 3) <= source_end and source_end <= finalized

        _ ->
          false
      end

    if covered? do
      {timing, endpoint}
    else
      reason = Map.get(closed, epoch)

      timing =
        if reason, do: elem(TurnTiming.invalidate_acoustic(timing, reason), 1), else: timing

      {%{
         timing
         | landmarks_us: Map.drop(timing.landmarks_us, [:acoustic_end, :observer_confirmed])
       }, nil}
    end
  end

  defp finalize_coverage(timing, _endpoint, _ids, _packets, _closed),
    do:
      {%{
         timing
         | landmarks_us: Map.drop(timing.landmarks_us, [:acoustic_end, :observer_confirmed])
       }, nil}

  defp source_end([{g, t}], packets) do
    mapping = Enum.find(packets, &match?({:provider_sample_mapping, ^g, _, _}, &1))

    provider =
      Enum.find(packets, &match?({:provider_landmark, ^g, ^t, :provider_end_evidence, _, _}, &1))

    case {mapping, provider} do
      {{:provider_sample_mapping, ^g, provider_origin, source_origin},
       {:provider_landmark, ^g, ^t, _, _, samples}}
      when samples >= provider_origin ->
        source_origin + samples - provider_origin

      _ ->
        nil
    end
  end

  defp source_end(_, _), do: nil

  defp segment_bounds([{g, _}] = ids, packets) do
    finish = source_end(ids, packets)

    previous =
      for {:provider_landmark, ^g, t, :provider_end_evidence, _, _} <- packets,
          endpoint = source_end([{g, t}], packets),
          is_integer(endpoint) and is_integer(finish) and endpoint < finish,
          do: endpoint

    origin =
      case Enum.find(packets, &match?({:provider_sample_mapping, ^g, _, _}, &1)) do
        {:provider_sample_mapping, ^g, _, start} -> start
        _ -> nil
      end

    {Enum.max(previous, fn -> origin end), finish}
  end

  defp segment_bounds(_, _), do: {nil, nil}

  defp source_bounds([{g, _}] = ids, packets, previous) do
    previous_ids =
      for {:provider_landmark, ^g, t, :provider_end_evidence, ^previous, _} <- packets,
          do: {g, t}

    origin =
      case Enum.find(packets, &match?({:provider_sample_mapping, ^g, _, _}, &1)) do
        {:provider_sample_mapping, ^g, _, start} -> start
        _ -> nil
      end

    start =
      case {origin, source_end(previous_ids, packets)} do
        {nil, previous_end} -> previous_end
        {origin, nil} -> origin
        {origin, previous_end} -> max(origin, previous_end)
      end

    {start, source_end(ids, packets)}
  end

  defp source_bounds(_, _, _), do: {nil, nil}

  defp within_source?({:acoustic_boundary, _, kind, sample, _, _, _, _}, {start, finish}) do
    after_start =
      is_nil(start) or if(kind == :speech_started, do: sample >= start, else: sample > start)

    before_end =
      is_nil(finish) or if(kind == :speech_started, do: sample < finish, else: sample <= finish)

    after_start and before_end
  end

  defp current_progress(state, {:acoustic_progress, epoch, _, finalized}) do
    case {Map.has_key?(state.closed_epochs, epoch), Map.get(state.packets, {:progress, epoch})} do
      {true, {:acoustic_progress, _, _, old}} when finalized > old ->
        {:error, :conflicting_evidence}

      {true, nil} ->
        {:error, :conflicting_evidence}

      _ ->
        :ok
    end
  end

  defp current_progress(_state, _packet), do: :ok

  defp close_epochs(state, {:reset, next, reason, _}) do
    reason =
      case reason do
        :audio_gap -> :audio_gap
        :source_replaced -> :source_changed
        :partial_start -> :partial_start
        _ -> :inference_reset
      end

    closed =
      Enum.reduce(state.packets, state.closed_epochs, fn
        {{:progress, epoch}, _}, acc when epoch <= next -> Map.put_new(acc, epoch, reason)
        {{:acoustic, epoch, _, _}, _}, acc when epoch <= next -> Map.put_new(acc, epoch, reason)
        _, acc -> acc
      end)

    %{state | closed_epochs: closed}
  end

  defp close_epochs(state, _packet), do: state

  defp boundary_reason(:partial_start), do: :partial_start
  defp boundary_reason(_), do: :clock_uncertain

  defp observe_time(timing, kind, offset) do
    case TurnTiming.observe(timing, kind, offset, timing.clock_id) do
      {:ok, timing} -> timing
      _ -> timing
    end
  end

  defp identifier(value),
    do:
      value
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

  defp bounded!(options, key, default, range) do
    value = Keyword.get(options, key, default)

    if is_integer(value) and value in range,
      do: value,
      else: raise(ArgumentError, "invalid report capacity")
  end
end
