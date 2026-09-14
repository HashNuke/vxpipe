defmodule Vxpipe.CallEngine.RoomRecording.Preparation do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.Stream
  alias Vxpipe.CallEngine.RoomMixer
  alias Vxpipe.CallEngine.RoomRecording.{State, Streams}

  @maximum_tracks 128

  def prepare(%State{} = state, tracks, interval) do
    config = state.configuration

    with {:ok, policy} <- RoomMixer.recording_configuration(config.mixer, config.recording_token),
         :ok <- current_policy(policy, tracks, interval),
         :ok <- validate_tracks(tracks, config, policy) do
      state = require_tracks(state, tracks, interval, policy.permitted?)
      prepare_outputs(state, policy.format)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp current_policy(%{interval: current}, _tracks, interval) when current != interval,
    do: {:error, :stale_recording_policy}

  defp current_policy(%{permitted?: false}, tracks, _interval) when tracks != [],
    do: {:error, :recording_not_permitted}

  defp current_policy(_policy, _tracks, _interval), do: :ok

  @doc false
  def validate_tracks(tracks, config, policy) when is_list(tracks) do
    if length(tracks) <= @maximum_tracks and length(tracks) == length(Enum.uniq(tracks)) and
         Enum.all?(tracks, &valid_track?(&1, config, policy)) do
      :ok
    else
      {:error, :invalid_recording_tracks}
    end
  end

  def validate_tracks(_tracks, _config, _policy), do: {:error, :invalid_recording_tracks}

  defp valid_track?({:individual_track, participant, _connection, _track} = mode, config, policy) do
    MapSet.member?(policy.present, participant) and
      Enum.any?(config.targets, &selected?(&1, mode)) and
      match?({:ok, _stream}, Stream.new(config.identity, mode, policy.format))
  end

  defp valid_track?(_mode, _config, _policy), do: false

  defp require_tracks(state, tracks, interval, permitted?) do
    streams =
      Map.new(state.streams, fn {id, stream} ->
        modes =
          case stream.target do
            :full_mix -> MapSet.new([:full_mix])
            target -> tracks |> Enum.filter(&selected?(target, &1)) |> MapSet.new()
          end

        {id, %{stream | required_modes: if(permitted?, do: modes, else: MapSet.new())}}
      end)

    %{state | streams: streams, prepared_interval: interval}
  end

  defp prepare_outputs(state, format) do
    Enum.reduce_while(state.streams, {:ok, state}, fn {id, stream}, {:ok, state} ->
      {outcome, stream} = prepare_stream(stream, state.configuration, format)
      state = %{state | streams: Map.put(state.streams, id, stream)}

      case outcome do
        :ok -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp prepare_stream(stream, config, format) do
    stream.required_modes
    |> Enum.sort()
    |> Enum.reduce_while({:ok, stream}, fn mode, {:ok, stream} ->
      case Streams.prepare_output(stream, mode, format, config) do
        {:ok, stream} -> {:cont, {:ok, stream}}
        {:error, reason} -> {:halt, {{:error, reason}, stream}}
      end
    end)
  end

  defp selected?({:individual_tracks, participants}, {:individual_track, participant, _, _}),
    do: participant in participants

  defp selected?(_target, _mode), do: false
end
