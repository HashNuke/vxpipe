defmodule Vxpipe.CallEngine.MediaPolicy.Candidate do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}

  @enforce_keys [:authority, :base_snapshot, :snapshot]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          authority: pid(),
          base_snapshot: Snapshot.t(),
          snapshot: Snapshot.t()
        }

  def new(authority, %MapSet{} = present, state) do
    with {:ok, contributions} <- contributions(present, state.participant_policies),
         {:ok, effective} <-
           Effective.compose(state.host_ceiling, state.normal_policy, contributions),
         {:ok, snapshot} <- snapshot(present, effective, state.snapshot) do
      {:ok, %__MODULE__{authority: authority, base_snapshot: state.snapshot, snapshot: snapshot}}
    end
  end

  def new(_authority, _present, _state), do: {:error, :invalid_presence}

  def validate(%__MODULE__{snapshot: %Snapshot{}} = candidate, authority, state) do
    cond do
      candidate.authority != authority ->
        {:error, :invalid_candidate}

      candidate.base_snapshot != state.snapshot ->
        {:error, :stale_candidate}

      true ->
        case new(authority, candidate.snapshot.present_participant_ids, state) do
          {:ok, ^candidate} -> :ok
          _invalid -> {:error, :invalid_candidate}
        end
    end
  end

  def validate(_candidate, _authority, _state), do: {:error, :invalid_candidate}

  defp contributions(present, policies) do
    Enum.reduce_while(present, {:ok, %{}}, fn participant, {:ok, contributions} ->
      cond do
        not is_binary(participant) ->
          {:halt, {:error, :invalid_presence}}

        Map.has_key?(policies, participant) ->
          {:cont, {:ok, Map.put(contributions, participant, Map.fetch!(policies, participant))}}

        true ->
          {:halt, {:error, :unknown_participant}}
      end
    end)
  end

  defp snapshot(present, effective, current) do
    if present == current.present_participant_ids do
      {:ok, current}
    else
      Snapshot.prepare(
        %Snapshot{
          revision: current.revision + 1,
          present_participant_ids: present,
          effective: effective
        },
        current
      )
    end
  end
end
