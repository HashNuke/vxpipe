defmodule Vxpipe.CallEngine.MediaPolicy.Snapshot do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Intervals}

  @enforce_keys [:revision, :present_participant_ids, :effective]
  defstruct @enforce_keys ++ [intervals: nil]

  @type t :: %__MODULE__{
          revision: non_neg_integer(),
          present_participant_ids: MapSet.t(String.t()),
          effective: Effective.t(),
          intervals: map() | nil
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = snapshot) do
    is_integer(snapshot.revision) and snapshot.revision >= 0 and
      is_struct(snapshot.present_participant_ids, MapSet) and
      Enum.all?(snapshot.present_participant_ids, &is_binary/1) and
      Effective.valid?(snapshot.effective) and
      Intervals.valid?(snapshot.intervals, snapshot.revision)
  end

  def valid?(_snapshot), do: false

  @spec prepare(t(), t() | nil) :: {:ok, t()} | {:error, atom()}
  def prepare(%__MODULE__{} = snapshot, previous) do
    with :ok <- validate_transition(snapshot, previous) do
      {:ok, %{snapshot | intervals: Intervals.next(previous, snapshot)}}
    end
  end

  @spec interval(t(), :recording) :: non_neg_integer()
  def interval(%__MODULE__{intervals: nil, revision: revision}, :recording), do: revision

  def interval(%__MODULE__{intervals: intervals}, :recording),
    do: Map.fetch!(intervals, :recording)

  @spec interval(t(), :speech_to_text | :audio_input | :audio_output, String.t()) ::
          non_neg_integer()
  def interval(%__MODULE__{intervals: nil, revision: revision}, _scope, _participant),
    do: revision

  def interval(%__MODULE__{} = snapshot, scope, participant) do
    snapshot.intervals |> Map.fetch!(scope) |> Map.get(participant, snapshot.revision)
  end

  @spec validate_transition(t(), nil | t()) ::
          :ok | {:error, :invalid_policy | :stale_policy_revision | :unexpected_policy_revision}
  def validate_transition(%__MODULE__{} = snapshot, current) do
    cond do
      not valid?(snapshot) -> {:error, :invalid_policy}
      is_nil(current) -> :ok
      snapshot.revision <= current.revision -> {:error, :stale_policy_revision}
      snapshot.revision == current.revision + 1 -> :ok
      true -> {:error, :unexpected_policy_revision}
    end
  end
end
