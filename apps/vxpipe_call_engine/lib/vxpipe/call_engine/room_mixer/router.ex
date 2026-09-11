defmodule Vxpipe.CallEngine.RoomMixer.Router do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Effective

  @spec sources(
          %{String.t() => NormalizedFrame.t()},
          String.t(),
          Vxpipe.CallEngine.Media.MixedFrame.mode(),
          Effective.t()
        ) :: [NormalizedFrame.t()]
  def sources(bucket, recipient_id, mode, %Effective{} = policy) do
    bucket
    |> Enum.filter(fn {source_id, _frame} ->
      selected?(mode, source_id, recipient_id) and
        Effective.audio_route_permitted?(policy, source_id, recipient_id)
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @spec recording_sources(
          %{String.t() => NormalizedFrame.t()},
          :full_mix | {:individual_track, String.t()}
        ) :: [NormalizedFrame.t()]
  def recording_sources(bucket, mode) do
    bucket
    |> Enum.filter(fn {source_id, _frame} -> selected?(mode, source_id, nil) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp selected?(:mix_minus, source_id, recipient_id), do: source_id != recipient_id
  defp selected?(:full_mix, _source_id, _recipient_id), do: true

  defp selected?({:individual_track, selected_source_id}, source_id, _recipient_id),
    do: source_id == selected_source_id
end
