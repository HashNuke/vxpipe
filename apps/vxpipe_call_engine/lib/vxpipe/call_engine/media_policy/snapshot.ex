defmodule Vxpipe.CallEngine.MediaPolicy.Snapshot do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Effective

  @enforce_keys [:revision, :present_participant_ids, :effective]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          revision: non_neg_integer(),
          present_participant_ids: MapSet.t(String.t()),
          effective: Effective.t()
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = snapshot) do
    is_integer(snapshot.revision) and snapshot.revision >= 0 and
      is_struct(snapshot.present_participant_ids, MapSet) and
      Enum.all?(snapshot.present_participant_ids, &is_binary/1) and
      Effective.valid?(snapshot.effective)
  end

  def valid?(_snapshot), do: false

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
