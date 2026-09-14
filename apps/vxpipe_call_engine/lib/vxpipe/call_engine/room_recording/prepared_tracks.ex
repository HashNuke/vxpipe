defmodule Vxpipe.CallEngine.RoomRecording.PreparedTracks do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.{PreparedWriter, Stream}
  alias Vxpipe.CallEngine.RoomRecording.Output

  def stage(state, tracks, previous, options, permitted?) do
    selections =
      Map.new(state.streams, fn {id, stream} ->
        {id, if(permitted?, do: modes(stream.target, tracks), else: MapSet.new())}
      end)

    required = for {id, modes} <- selections, mode <- modes, do: {id, mode}

    result =
      Enum.reduce_while(Enum.sort(required), {:ok, %{}}, fn {id, mode} = key, {:ok, outputs} ->
        cond do
          Map.has_key?(Map.fetch!(state.streams, id).outputs, mode) ->
            {:cont, {:ok, outputs}}

          Map.has_key?(previous, key) ->
            {:cont, {:ok, Map.put(outputs, key, Map.fetch!(previous, key))}}

          true ->
            case open(state, mode, options) do
              {:ok, output} -> {:cont, {:ok, Map.put(outputs, key, output)}}
              {:error, reason} -> {:halt, {:error, reason, outputs}}
            end
        end
      end)

    case result do
      {:ok, outputs} ->
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

  defp modes(:full_mix, _tracks), do: MapSet.new([:full_mix])

  defp modes({:individual_tracks, participants}, tracks),
    do:
      MapSet.new(Enum.filter(tracks, fn {:individual_track, id, _, _} -> id in participants end))

  defp open(state, mode, options) do
    config = state.configuration

    options =
      options
      |> Keyword.take([:owner, :attempt_id, :deadline_ms])
      |> Keyword.put(:writer_options, config.writer_options)
      |> Keyword.put(:source, self())

    with {:ok, stream} <- Stream.new(config.identity, mode, state.format),
         {:ok, lease} <- PreparedWriter.start(config.writer, stream, options),
         do:
           {:ok, %{lease: lease, output: %Output{writer_handle: lease.handle, next_sequence: 0}}}
  end
end
