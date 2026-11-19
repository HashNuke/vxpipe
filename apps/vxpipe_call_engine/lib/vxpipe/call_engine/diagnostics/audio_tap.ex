defmodule Vxpipe.CallEngine.Diagnostics.AudioTap do
  @moduledoc "Observation of accepted PCM fenced by allocation, policy revision and exact media source."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.Media.AudioFrame
  @enforce_keys [:handoff, :generation, :policy_revision, :track_id, :source_epoch]
  @derive {Inspect, only: [:policy_revision]}
  defstruct @enforce_keys

  def new(
        %CaptureHandoff{} = handoff,
        generation,
        revision,
        %{track_id: track, source_epoch: epoch} = source
      )
      when is_reference(generation) and is_integer(revision) and revision >= 0 and
             is_binary(track) and byte_size(track) in 1..256 and is_reference(epoch) and
             map_size(source) == 2 do
    if handoff.owner == self() and CaptureHandoff.current?(handoff) do
      {:ok,
       %__MODULE__{
         handoff: handoff,
         generation: generation,
         policy_revision: revision,
         track_id: :binary.copy(track),
         source_epoch: epoch
       }}
    else
      {:error, :unavailable}
    end
  end

  def new(_handoff, _generation, _revision, _source), do: {:error, :unavailable}

  def offer(nil, _generation, _revision, _frame), do: :ok

  def offer(tap, generation, revision, %AudioFrame{track_id: track, source_epoch: epoch} = frame) do
    if generation == tap.generation and revision == tap.policy_revision and
         track == tap.track_id and epoch == tap.source_epoch do
      _ = CaptureHandoff.offer(tap.handoff, {:audio, frame})
      :ok
    else
      close(tap)
    end
  end

  def offer(tap, _generation, _revision, _invalid), do: close(tap)

  def replace(tap, tap), do: :ok

  def replace(%__MODULE__{handoff: old}, %__MODULE__{handoff: new})
      when old.token == new.token, do: {:error, :unavailable}

  def replace(previous, _next), do: close(previous)

  def close(nil), do: :ok
  def close(%__MODULE__{handoff: handoff}), do: CaptureHandoff.close(handoff)

  def policy_change(nil, _revision), do: :ok
  def policy_change(%__MODULE__{policy_revision: revision}, revision), do: :ok
  def policy_change(tap, _revision), do: close(tap)
end
