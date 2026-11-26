defmodule Vxpipe.CallEngine.RoomRecording.PreparedTracks do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.{PreparedWriter, Stream}
  alias Vxpipe.CallEngine.RoomRecording.{Output, Streams}

  def stage(state, tracks, previous, options, permitted?) do
    selections =
      Map.new(state.streams, fn {id, stream} ->
        {id, if(permitted?, do: modes(stream.target, tracks), else: MapSet.new())}
      end)

    required = for {id, modes} <- selections, mode <- modes, do: {id, mode}
    required_set = MapSet.new(required)
    reserved = reserved_reconnections(state, previous, required_set)

    result =
      Enum.reduce_while(Enum.sort(required), {:ok, {%{}, %{}}}, fn
        {id, mode} = key, {:ok, {outputs, allocated}} ->
          cond do
            Map.has_key?(Map.fetch!(state.streams, id).outputs, mode) ->
              {:cont, {:ok, {outputs, allocated}}}

            Map.has_key?(previous, key) ->
              {:cont, {:ok, {Map.put(outputs, key, Map.fetch!(previous, key)), allocated}}}

            true ->
              reconnection = next_for_candidate(mode, reserved, allocated)

              case open(state, mode, reconnection, options) do
                {:ok, output} ->
                  allocated =
                    if is_integer(reconnection) do
                      Map.update(
                        allocated,
                        participant(mode),
                        MapSet.new([reconnection]),
                        &MapSet.put(&1, reconnection)
                      )
                    else
                      allocated
                    end

                  {:cont, {:ok, {Map.put(outputs, key, output), allocated}}}

                {:error, reason} ->
                  {:halt, {:error, reason, outputs}}
              end
          end
      end)

    case result do
      {:ok, {outputs, _allocated}} ->
        close(Map.drop(previous, Map.keys(outputs)))
        {:ok, selections, outputs}

      {:error, reason, opened} ->
        close(Map.drop(opened, Map.keys(previous)))
        {:error, reason}
    end
  end

  def streams(state, pending) do
    Map.new(state.streams, fn {id, stream} ->
      added =
        for {{^id, mode}, %{output: output}} <- pending.outputs, into: %{}, do: {mode, output}

      {id,
       %{
         stream
         | outputs: Map.merge(stream.outputs, added),
           required_modes: Map.fetch!(pending.selections, id),
           subscription: Map.fetch!(pending.subscriptions, id)
       }}
    end)
  end

  def consistent?(state, pending) do
    Enum.all?(pending.outputs, fn {{id, mode}, _output} ->
      not Map.has_key?(Map.fetch!(state.streams, id).outputs, mode)
    end)
  end

  def adopt(outputs) do
    Enum.reduce_while(outputs, :ok, fn {_key, %{lease: lease}}, :ok ->
      case PreparedWriter.adopt(lease) do
        :ok -> {:cont, :ok}
        _unavailable -> {:halt, {:error, :policy_not_ready}}
      end
    end)
  end

  def close(outputs),
    do: Enum.each(outputs, fn {_key, %{lease: lease}} -> PreparedWriter.retire(lease) end)

  defp modes(:room_track, _tracks), do: MapSet.new([:room_track])

  defp modes({:individual_tracks, participants}, tracks),
    do:
      MapSet.new(for {:individual_track, id, _, _} = mode <- tracks, id in participants, do: mode)

  defp participant({:individual_track, participant, _, _}), do: participant
  defp participant(_mode), do: nil

  defp next_for_candidate(:room_track, _reserved, _allocated), do: nil

  defp next_for_candidate({:individual_track, participant, _, _} = _mode, reserved, allocated) do
    used =
      MapSet.union(
        Map.get(reserved, participant, MapSet.new()),
        Map.get(allocated, participant, MapSet.new())
      )

    Streams.smallest_free(used)
  end

  # Actual suffixes already assigned to retained live/candidate outputs, keyed
  # by participant. Live outputs are always retained; candidate outputs are
  # retained when still required and not already live. Reserving the full set
  # up front keeps sorted allocation from reusing a staged suffix that sorts
  # later (for example existing staged `z` when opening new `a`).
  defp reserved_reconnections(state, previous, required_set) do
    live_entries =
      for {_id, stream} <- state.streams,
          {mode, output} <- stream.outputs,
          do: {mode, output}

    retained_entries =
      for {{id, mode} = key, value} <- previous,
          MapSet.member?(required_set, key),
          not live_has?(state, id, mode),
          output = candidate_output(value),
          not is_nil(output),
          do: {mode, output}

    participants =
      (live_entries ++ retained_entries)
      |> Enum.map(fn
        {{:individual_track, participant, _, _}, _} -> participant
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Map.new(participants, fn participant ->
      live_used = Streams.used_reconnections(live_entries, participant)
      retained_used = Streams.used_reconnections(retained_entries, participant)
      {participant, MapSet.union(live_used, retained_used)}
    end)
  end

  defp live_has?(state, id, mode) do
    case Map.fetch(state.streams, id) do
      {:ok, stream} -> Map.has_key?(stream.outputs, mode)
      :error -> false
    end
  end

  defp candidate_output(%{output: %Output{} = output}), do: output
  defp candidate_output(_other), do: nil

  defp open(state, mode, reconnection, options) do
    config = state.configuration

    options =
      options
      |> Keyword.take([:owner, :attempt_id, :deadline_ms])
      |> Keyword.put(:writer_options, config.writer_options)
      |> Keyword.put(:source, self())

    identity = Streams.identity_with_reconnection(config, mode, reconnection)

    with {:ok, stream} <- Stream.new(identity, mode, state.format),
         {:ok, lease} <- PreparedWriter.start(config.writer, stream, options),
         do:
           {:ok,
            %{
              lease: lease,
              output: %Output{
                writer_handle: lease.handle,
                next_sequence: 0,
                reconnection: reconnection
              }
            }}
  end
end
